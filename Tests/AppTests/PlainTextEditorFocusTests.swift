import AppKit
@testable import CrossPost
import SwiftUI
import XCTest

@MainActor
final class PlainTextEditorFocusTests: XCTestCase {
    /// With keyboard navigation on, AppKit would otherwise give initial focus to
    /// the first key view — a header button — instead of the post body.
    func testEditorTakesFocusWhenItAppearsBehindAButton() {
        let content = VStack {
            Button("New draft…") {}
            PlainTextEditor(text: .constant(""))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        let focused = expectation(description: "editor becomes first responder")
        func poll() {
            if window.firstResponder is NSTextView {
                focused.fulfill()
            } else {
                DispatchQueue.main.async(execute: poll)
            }
        }
        poll()
        wait(for: [focused], timeout: 2)
    }
}
