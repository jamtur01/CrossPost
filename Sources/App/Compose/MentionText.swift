import AppKit

extension NSAttributedString.Key {
    static let crossPostMention = NSAttributedString.Key("net.kartar.crosspost.mention")
}

/// Who a mention addresses and the text it was inserted as. Boxed per mention so
/// adjacent mentions stay separate attribute runs (an `NSObject` compares by
/// identity, so runs never coalesce).
final class MentionMark: NSObject {
    let person: MentionPerson
    let label: String

    init(_ person: MentionPerson, label: String) {
        self.person = person
        self.label = label
    }
}

/// Mentions live in the text storage as `MentionMark` attribute runs, so AppKit
/// moves them with every edit and undo restores them with their text. A run
/// counts as a mention only while its text is still exactly its label: an edit
/// inside one makes it plain text without removing the mark, so undoing that edit
/// makes it a mention again.
@MainActor
enum MentionText {
    static func plainAttributes(for textView: NSTextView) -> [NSAttributedString.Key: Any] {
        [.font: textView.font ?? .systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]
    }

    static func markAttributes(_ person: MentionPerson, label: String) -> [NSAttributedString.Key: Any] {
        [.crossPostMention: MentionMark(person, label: label)]
    }

    private static func whole(_ storage: NSAttributedString) -> NSRange {
        NSRange(location: 0, length: storage.length)
    }

    private struct MarkRun {
        let mark: MentionMark
        let range: NSRange
        /// The run's text is still exactly the mark's label.
        let intact: Bool
    }

    private static func runs(in storage: NSAttributedString) -> [MarkRun] {
        var runs: [MarkRun] = []
        let text = storage.string as NSString
        storage.enumerateAttribute(.crossPostMention, in: whole(storage)) { value, range, _ in
            guard let mark = value as? MentionMark else { return }
            runs.append(MarkRun(mark: mark, range: range, intact: text.substring(with: range) == mark.label))
        }
        return runs
    }

    /// The intact mentions, in text order.
    static func spans(in storage: NSAttributedString) -> [MentionSpan] {
        runs(in: storage).filter(\.intact).map {
            MentionSpan(location: $0.range.location, length: $0.range.length, person: $0.mark.person)
        }
    }

    /// Accent-colours intact mentions and resets broken ones to plain text.
    /// Attribute-only: call it outside an edit, or the caret can move.
    static func recolor(_ storage: NSTextStorage) {
        let runs = runs(in: storage)
        guard !runs.isEmpty else { return }
        storage.beginEditing()
        for run in runs {
            let color = run.intact ? NSColor.controlAccentColor : NSColor.textColor
            storage.addAttribute(.foregroundColor, value: color, range: run.range)
        }
        storage.endEditing()
    }

    /// Replaces all marks in `textView` with `spans` (skipping any outside the text).
    static func apply(_ spans: [MentionSpan], to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        storage.beginEditing()
        storage.removeAttribute(.crossPostMention, range: whole(storage))
        storage.addAttributes(plainAttributes(for: textView), range: whole(storage))
        for span in spans where NSMaxRange(span.range) <= storage.length {
            storage.addAttributes(markAttributes(span.person, label: text.substring(with: span.range)),
                                  range: span.range)
        }
        storage.endEditing()
    }

    /// The intact mention ending exactly at `location`, if any.
    static func mention(endingAt location: Int, in storage: NSAttributedString) -> NSRange? {
        runs(in: storage).first { $0.intact && NSMaxRange($0.range) == location }?.range
    }

    /// The intact mention covering `index`, if any.
    static func mention(at index: Int, in storage: NSAttributedString) -> MentionSpan? {
        spans(in: storage).first { NSLocationInRange(index, $0.range) }
    }
}
