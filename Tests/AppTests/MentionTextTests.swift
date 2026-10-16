import AppKit
@testable import CrossPost
import SwiftUI
import XCTest

@MainActor
final class MentionTextTests: XCTestCase {
    private var text = ""
    private var mentions: [MentionSpan] = []
    private let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")

    private func makeEditor() -> (UndoableTextView, PlainTextEditor.Coordinator) {
        let textView = UndoableTextView()
        let coordinator = PlainTextEditor.Coordinator(
            text: Binding(get: { self.text }, set: { self.text = $0 }),
            mentions: Binding(get: { self.mentions }, set: { self.mentions = $0 }),
            editing: nil
        )
        coordinator.attach(to: textView)
        return (textView, coordinator)
    }

    func testInsertedMentionIsTrackedThroughEditsBeforeIt() {
        let (textView, coordinator) = makeEditor()
        textView.insertText("hi @pu", replacementRange: NSRange(location: 0, length: 0))
        coordinator.insert(person, replacing: NSRange(location: 3, length: 3))
        XCTAssertEqual(text, "hi @pup ")
        XCTAssertEqual(mentions, [MentionSpan(location: 3, length: 4, person: person)])

        textView.insertText("oh ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(mentions.map(\.location), [6])
    }

    func testTypingAfterMentionIsPlainText() {
        let (textView, coordinator) = makeEditor()
        coordinator.insert(person, replacing: NSRange(location: 0, length: 0))
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.insertText("x", replacementRange: textView.selectedRange())
        XCTAssertEqual(text, "@pupx ")
        XCTAssertEqual(mentions.map(\.length), [4])
    }

    func testEditingInsideMentionDropsIt() {
        let (textView, coordinator) = makeEditor()
        textView.allowsUndo = true
        textView.undoably { coordinator.insert(person, replacing: NSRange(location: 0, length: 0)) }
        textView.undoably { textView.insertText("X", replacementRange: NSRange(location: 2, length: 0)) }
        XCTAssertEqual(text, "@pXup ")
        XCTAssertEqual(mentions, [])

        textView.undo.undo()
        XCTAssertEqual(text, "@pup ")
        XCTAssertEqual(mentions, [MentionSpan(location: 0, length: 4, person: person)])
    }

    func testBackspaceAtEndDeletesWholeMention() {
        let (textView, coordinator) = makeEditor()
        textView.allowsUndo = true
        textView.undoably { coordinator.insert(person, replacing: NSRange(location: 0, length: 0)) }
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.undoably { textView.deleteBackward(nil) }
        XCTAssertEqual(text, " ")
        XCTAssertEqual(mentions, [])

        // Undo must bring back who the mention addresses, not just its text.
        textView.undo.undo()
        XCTAssertEqual(text, "@pup ")
        XCTAssertEqual(mentions, [MentionSpan(location: 0, length: 4, person: person)])
    }

    func testApplyingSpansRestoresMarks() throws {
        let (textView, _) = makeEditor()
        textView.string = "a @pup"
        MentionText.apply([MentionSpan(location: 2, length: 4, person: person)], to: textView)
        XCTAssertEqual(
            try MentionText.spans(in: XCTUnwrap(textView.textStorage)),
            [MentionSpan(location: 2, length: 4, person: person)]
        )
    }

    func testRestoredDraftKeepsItsMentions() {
        text = "hi @pup"
        mentions = [MentionSpan(location: 3, length: 4, person: person)]
        let editor = PlainTextEditor(text: Binding(get: { self.text }, set: { self.text = $0 }),
                                     mentions: Binding(get: { self.mentions }, set: { self.mentions = $0 }))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 300, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: editor)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(text, "hi @pup")
        XCTAssertEqual(mentions, [MentionSpan(location: 3, length: 4, person: person)])
    }

    func testArrowAndReturnPickFromSuggestions() async throws {
        let (textView, coordinator) = makeEditor()
        let people = [MentionPerson(blueskyHandle: "first.bsky.social", displayName: "First"),
                      MentionPerson(blueskyHandle: "second.bsky.social", displayName: "Second")]
        let completion = MentionCompletion(debounce: .zero) { _ in
            MentionDirectory.Results(people: people, failed: [])
        }
        coordinator.update(text: Binding(get: { self.text }, set: { self.text = $0 }),
                           mentions: Binding(get: { self.mentions }, set: { self.mentions = $0 }),
                           editing: MentionEditing(completion: completion, requestPairing: { _, _ in }))
        textView.insertText("hi @se", replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(completion.isActive)

        XCTAssertTrue(coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(text, "hi @second ")
        XCTAssertEqual(mentions.map(\.person), [people[1]])
        XCTAssertFalse(completion.isActive)
        XCTAssertFalse(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }
}

/// A text view with its own undo manager, since a bare one has no window to ask.
/// With no event loop to close undo groups, each edit gets an explicit group.
final class UndoableTextView: NSTextView {
    let undo: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()

    override var undoManager: UndoManager? {
        allowsUndo ? undo : nil
    }

    func undoably(_ edit: () -> Void) {
        undo.beginUndoGrouping()
        edit()
        breakUndoCoalescing()
        undo.endUndoGrouping()
    }
}
