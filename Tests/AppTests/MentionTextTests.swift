import AppKit
@testable import CrossPost
import SwiftUI
import XCTest

@MainActor
final class MentionTextTests: XCTestCase {
    private var text = ""
    private var mentions: [MentionSpan] = []
    private let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")

    private func makeEditor() -> (NSTextView, PlainTextEditor.Coordinator) {
        let textView = NSTextView()
        let coordinator = PlainTextEditor.Coordinator(
            text: Binding(get: { self.text }, set: { self.text = $0 }),
            mentions: Binding(get: { self.mentions }, set: { self.mentions = $0 }),
            editing: nil
        )
        textView.delegate = coordinator
        coordinator.textView = textView
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
        coordinator.insert(person, replacing: NSRange(location: 0, length: 0))
        textView.insertText("X", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(text, "@pXup ")
        XCTAssertEqual(mentions, [])
    }

    func testBackspaceAtEndDeletesWholeMention() {
        let (textView, coordinator) = makeEditor()
        coordinator.insert(person, replacing: NSRange(location: 0, length: 0))
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.deleteBackward(nil)
        XCTAssertEqual(text, " ")
        XCTAssertEqual(mentions, [])
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
}
