import AppKit
import SwiftUI

/// A multi-line text editor with no visible scroller (content still scrolls via
/// trackpad). `TextEditor`'s scroller can't be reliably hidden — especially when
/// macOS is set to always show scroll bars — so the compose box uses this instead.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.drawsBackground = false
            textView.font = .systemFont(ofSize: 15)
            textView.textContainerInset = NSSize(width: 2, height: 6)
            textView.isRichText = false
            textView.allowsUndo = true
            // Seed prefilled text (e.g. reply mentions) with the caret at the end,
            // so typing continues after the @handles rather than before them.
            textView.string = text
            textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Don't disturb an in-progress IME composition (CJK / dead keys).
        guard !textView.hasMarkedText(), textView.string != text else { return }
        // Setting `string` resets the selection to the start; preserve the caret,
        // clamped to the new length (e.g. after a programmatic prefill or clear).
        let selected = textView.selectedRange()
        textView.string = text
        let clamped = NSRange(location: min(selected.location, text.utf16.count), length: 0)
        textView.setSelectedRange(clamped)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
