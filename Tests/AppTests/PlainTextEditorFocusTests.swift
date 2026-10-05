import AppKit
@testable import CrossPost
import SwiftUI
import XCTest

@MainActor
final class PlainTextEditorFocusTests: XCTestCase {
    /// With keyboard navigation on, AppKit would otherwise give initial focus to
    /// the first key view — a header button — instead of the post body.
    func testEditorTakesFocusWhenItAppearsBehindAButton() {
        let window = host(VStack {
            Button("New draft…") {}
            PlainTextEditor(text: .constant(""))
        })
        defer { window.close() }

        waitUntil("editor becomes first responder") { window.firstResponder is NSTextView }
    }

    /// Discarding through the confirmation dialog replaces the editor; focus must
    /// land in the replacement once the dialog closes, not on the header button.
    func testReplacementEditorTakesFocusAfterConfirmationDialog() throws {
        let state = DialogHarnessState()
        let window = host(DialogHarness(state: state))
        defer { window.close() }
        waitUntil("first editor focused") { window.firstResponder is NSTextView }
        let original = try XCTUnwrap(window.firstResponder as? NSTextView)

        state.presented = true
        waitUntil("dialog shown") { window.attachedSheet != nil }
        let discard = try XCTUnwrap(
            window.attachedSheet?.contentView.flatMap { Self.button(titled: "Discard Draft", in: $0) }
        )
        discard.performClick(nil)
        waitUntil("dialog closed") { window.attachedSheet == nil }

        waitUntil("replacement editor focused") {
            guard let focused = window.firstResponder as? NSTextView else { return false }
            return focused !== original
        }
    }

    private func host(_ content: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let met = expectation(description: description)
        func poll() {
            if condition() {
                met.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll() }
            }
        }
        poll()
        wait(for: [met], timeout: 3)
    }

    private static func button(titled title: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == title {
            return button
        }
        for subview in view.subviews {
            if let match = button(titled: title, in: subview) {
                return match
            }
        }
        return nil
    }
}

@Observable
private final class DialogHarnessState {
    var presented = false
    var editorID = UUID()
}

/// Mirrors the compose column: a header button above the editor, and a
/// confirmation dialog whose destructive action swaps in a fresh editor.
private struct DialogHarness: View {
    @Bindable var state: DialogHarnessState

    var body: some View {
        VStack {
            Button("New draft…") { state.presented = true }
            PlainTextEditor(text: .constant("")).id(state.editorID)
        }
        .confirmationDialog("Discard this draft?", isPresented: $state.presented) {
            Button("Discard Draft", role: .destructive) { state.editorID = UUID() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
