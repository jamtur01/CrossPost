import AppKit
import SwiftUI

/// A multi-line text editor with no visible scroller (content still scrolls via
/// trackpad). `TextEditor`'s scroller can't be reliably hidden — especially when
/// macOS is set to always show scroll bars — so the compose box uses this instead.
/// What the compose editor needs for @-mentions: the autocomplete state and a
/// way to ask for a mention's account on one network to be chosen by hand.
struct MentionEditing {
    let completion: MentionCompletion
    let requestPairing: (MentionSpan, PostTarget) -> Void
}

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var mentions: Binding<[MentionSpan]>?
    var editing: MentionEditing?

    init(text: Binding<String>, mentions: Binding<[MentionSpan]>? = nil, editing: MentionEditing? = nil) {
        _text = text
        self.mentions = mentions
        self.editing = editing
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusOnFirstWindowTextView.scrollableTextView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            context.coordinator.textView = textView
            textView.drawsBackground = false
            textView.font = .systemFont(ofSize: 15)
            textView.textContainerInset = NSSize(width: 2, height: 6)
            textView.isRichText = false
            textView.allowsUndo = true
            // Seed prefilled text (e.g. reply mentions) with the caret at the end,
            // so typing continues after the @handles rather than before them.
            textView.string = text
            textView.typingAttributes = MentionText.plainAttributes(for: textView)
            if let mentions {
                MentionText.apply(mentions.wrappedValue, to: textView)
            }
            textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(text: $text, mentions: mentions, editing: editing)
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Don't disturb an in-progress IME composition (CJK / dead keys).
        guard !textView.hasMarkedText() else { return }
        if textView.string != text {
            // Setting `string` resets the selection to the start; preserve the caret,
            // clamped to the new length (e.g. after a programmatic prefill or clear).
            let selected = textView.selectedRange()
            textView.string = text
            if let mentions {
                MentionText.apply(mentions.wrappedValue, to: textView)
            }
            let clamped = NSRange(location: min(selected.location, text.utf16.count), length: 0)
            textView.setSelectedRange(clamped)
        } else if let mentions, let storage = textView.textStorage,
                  MentionText.spans(in: storage) != mentions.wrappedValue {
            // A mention changed outside the editor (an account chosen by hand).
            MentionText.apply(mentions.wrappedValue, to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(text: $text, mentions: mentions, editing: nil)
        coordinator.update(text: $text, mentions: mentions, editing: editing)
        return coordinator
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        private var text: Binding<String>
        private var mentions: Binding<[MentionSpan]>?
        private var editing: MentionEditing?

        init(text: Binding<String>, mentions: Binding<[MentionSpan]>?, editing: MentionEditing?) {
            self.text = text
            self.mentions = mentions
            self.editing = editing
        }

        /// Takes the latest bindings and points the completion's insertions here.
        func update(text: Binding<String>, mentions: Binding<[MentionSpan]>?, editing: MentionEditing?) {
            self.text = text
            self.mentions = mentions
            self.editing = editing
            editing?.completion.insert = { [weak self] person, range in
                self?.insert(person, replacing: range)
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard mentions != nil, let storage = textView.textStorage else { return true }
            if replacementString == "", range.length == 1,
               let whole = MentionText.mention(endingAt: NSMaxRange(range), in: storage) {
                deleteMention(whole, in: textView)
                return false
            }
            for run in MentionText.brokenMentions(by: range, in: storage) {
                storage.removeAttribute(.crossPostMention, range: run)
                storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: run)
            }
            textView.typingAttributes = MentionText.plainAttributes(for: textView)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            if let mentions, let storage = textView.textStorage {
                mentions.wrappedValue = MentionText.spans(in: storage)
            }
            updateCompletion(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateCompletion(textView)
        }

        /// Arrow keys, Return/Tab and Escape drive an open suggestion list. Otherwise
        /// Tab / Shift-Tab move focus to the next/previous control rather than
        /// inserting a tab character — the expected behavior for a compose field.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if let completion = editing?.completion, completion.isActive,
               handleCompletionCommand(commandSelector, completion) {
                return true
            }
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false
            }
        }

        private func handleCompletionCommand(_ selector: Selector, _ completion: MentionCompletion) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                completion.moveSelection(by: -1)
            case #selector(NSResponder.moveDown(_:)):
                completion.moveSelection(by: 1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                guard completion.selected != nil else { return false }
                completion.choose()
            case #selector(NSResponder.cancelOperation(_:)):
                completion.dismiss()
            default:
                return false
            }
            return true
        }

        private func updateCompletion(_ textView: NSTextView) {
            guard let completion = editing?.completion, let storage = textView.textStorage else { return }
            let caret = textView.selectedRange()
            guard caret.length == 0, MentionText.mention(endingAt: caret.location, in: storage) == nil else {
                completion.dismiss()
                return
            }
            completion.update(text: textView.string, caret: caret.location)
        }

        /// Replaces `range` with the mention's visible text plus a space, as one
        /// undoable edit, leaving the caret after the space.
        func insert(_ person: MentionPerson, replacing range: NSRange) {
            guard let textView, let storage = textView.textStorage else { return }
            let visible = person.visibleText
            let inserted = visible + " "
            guard textView.shouldChangeText(in: range, replacementString: inserted) else { return }
            storage.replaceCharacters(in: range, with: NSAttributedString(
                string: inserted, attributes: MentionText.plainAttributes(for: textView)
            ))
            storage.addAttributes(MentionText.markAttributes(person),
                                  range: NSRange(location: range.location, length: visible.utf16.count))
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + inserted.utf16.count, length: 0))
        }

        private func deleteMention(_ range: NSRange, in textView: NSTextView) {
            guard textView.shouldChangeText(in: range, replacementString: "") else { return }
            textView.textStorage?.replaceCharacters(in: range, with: "")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
        }

        /// Right-clicking a mention offers choosing its account on either network,
        /// to fill a missing one or re-point an existing one.
        func textView(_ view: NSTextView, menu: NSMenu, for _: NSEvent, at charIndex: Int) -> NSMenu? {
            guard editing != nil, let storage = view.textStorage, charIndex < storage.length else { return menu }
            var run = NSRange()
            guard let mark = storage.attribute(.crossPostMention, at: charIndex, effectiveRange: &run)
                as? MentionMark else { return menu }
            let span = MentionSpan(location: run.location, length: run.length, person: mark.person)
            menu.insertItem(.separator(), at: 0)
            for target in PostTarget.allCases.reversed() {
                let item = NSMenuItem(title: "Choose \(target.displayName) Account…",
                                      action: #selector(choosePairing(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = PairingChoice(span: span, target: target)
                menu.insertItem(item, at: 0)
            }
            return menu
        }

        @objc private func choosePairing(_ item: NSMenuItem) {
            guard let choice = item.representedObject as? PairingChoice else { return }
            editing?.requestPairing(choice.span, choice.target)
        }
    }
}

/// A context-menu item's payload: which mention and which network to choose for.
private final class PairingChoice: NSObject {
    let span: MentionSpan
    let target: PostTarget

    init(span: MentionSpan, target: PostTarget) {
        self.span = span
        self.target = target
    }
}

/// Takes keyboard focus the first time it joins a window, so typing goes straight
/// to the post. Otherwise, with keyboard navigation on, AppKit focuses the first
/// key view (a header button) and draws its focus ring. SwiftUI can create the
/// view well before inserting it into a window, hence the window hook.
private final class FocusOnFirstWindowTextView: NSTextView {
    private var hasTakenFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasTakenFocus, window != nil else { return }
        hasTakenFocus = true
        // Defer past the insertion pass so AppKit's own initial-focus choice
        // doesn't override this one.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}
