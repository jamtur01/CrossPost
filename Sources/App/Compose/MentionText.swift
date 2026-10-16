import AppKit

extension NSAttributedString.Key {
    static let crossPostMention = NSAttributedString.Key("net.kartar.crosspost.mention")
}

/// Boxed per mention so adjacent mentions stay separate attribute runs (an
/// `NSObject` compares by identity, so runs never coalesce).
final class MentionMark: NSObject {
    let person: MentionPerson
    init(_ person: MentionPerson) {
        self.person = person
    }
}

/// Mentions live in the text storage as `MentionMark` attribute runs, so AppKit
/// moves them with every edit and the spans are read back rather than tracked.
@MainActor
enum MentionText {
    static func plainAttributes(for textView: NSTextView) -> [NSAttributedString.Key: Any] {
        [.font: textView.font ?? .systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]
    }

    static func markAttributes(_ person: MentionPerson) -> [NSAttributedString.Key: Any] {
        [.crossPostMention: MentionMark(person), .foregroundColor: NSColor.controlAccentColor]
    }

    private static func whole(_ storage: NSAttributedString) -> NSRange {
        NSRange(location: 0, length: storage.length)
    }

    static func spans(in storage: NSAttributedString) -> [MentionSpan] {
        var spans: [MentionSpan] = []
        storage.enumerateAttribute(.crossPostMention, in: whole(storage)) { value, range, _ in
            guard let mark = value as? MentionMark else { return }
            spans.append(MentionSpan(location: range.location, length: range.length, person: mark.person))
        }
        return spans
    }

    /// Replaces all marks in `textView` with `spans` (skipping any outside the text).
    static func apply(_ spans: [MentionSpan], to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.removeAttribute(.crossPostMention, range: whole(storage))
        storage.addAttributes(plainAttributes(for: textView), range: whole(storage))
        for span in spans where NSMaxRange(span.range) <= storage.length {
            storage.addAttributes(markAttributes(span.person), range: span.range)
        }
        storage.endEditing()
    }

    /// The mention run ending exactly at `location`, if any.
    static func mention(endingAt location: Int, in storage: NSAttributedString) -> NSRange? {
        guard location > 0, location <= storage.length else { return nil }
        var range = NSRange()
        guard storage.attribute(.crossPostMention, at: location - 1, effectiveRange: &range) is MentionMark,
              NSMaxRange(range) == location else { return nil }
        return range
    }

    /// Mention runs an edit of `range` would break: any it overlaps, or an
    /// insertion strictly inside one. Edits at a run's edges leave it intact.
    static func brokenMentions(by range: NSRange, in storage: NSAttributedString) -> [NSRange] {
        var broken: [NSRange] = []
        storage.enumerateAttribute(.crossPostMention, in: whole(storage)) { value, run, _ in
            guard value is MentionMark else { return }
            let overlaps = NSIntersectionRange(run, range).length > 0
            let insideInsertion = range.length == 0 && range.location > run.location
                && range.location < NSMaxRange(run)
            if overlaps || insideInsertion {
                broken.append(run)
            }
        }
        return broken
    }
}
