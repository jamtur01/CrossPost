import Foundation

struct Attachment: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var imageData: Data
    var altText: String

    init(id: UUID = UUID(), imageData: Data, altText: String = "") {
        self.id = id
        self.imageData = imageData
        self.altText = altText
    }
}

struct DraftPost: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var text: String
    var attachments: [Attachment]
    /// Mastodon visibility for this post; ignored by Bluesky.
    var visibility: PostVisibility
    /// Mentions picked from autocomplete, rendered per network at post time.
    var mentions: [MentionSpan]

    init(id: UUID = UUID(), text: String = "", attachments: [Attachment] = [],
         visibility: PostVisibility = .public, mentions: [MentionSpan] = []) {
        self.id = id
        self.text = text
        self.attachments = attachments
        self.visibility = visibility
        self.mentions = mentions
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, attachments, visibility, mentions
    }

    /// Drafts saved before mentions existed have no `mentions` key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        attachments = try container.decode([Attachment].self, forKey: .attachments)
        visibility = try container.decode(PostVisibility.self, forKey: .visibility)
        mentions = try container.decodeIfPresent([MentionSpan].self, forKey: .mentions) ?? []
    }

    /// True when there is nothing to post: no text (after trimming) and no images.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }

    /// This post as `target` receives it: each mention replaced with that
    /// network's form.
    func rendered(for target: PostTarget) -> DraftPost {
        var copy = self
        copy.mentions = []
        copy.text = renderedParts(for: target).map(\.text).joined()
        return copy
    }

    /// The text `target` receives, split into typed text and mentions so a
    /// preview can show which mentions fell back to plain text. A span outside
    /// the text, or overlapping an earlier one, is left as typed.
    func renderedParts(for target: PostTarget) -> [RenderedPart] {
        let source = text as NSString
        var parts: [RenderedPart] = []
        var cursor = 0
        for span in mentions.sorted(by: { $0.location < $1.location })
            where span.location >= cursor && NSMaxRange(span.range) <= source.length {
            if span.location > cursor {
                let typed = NSRange(location: cursor, length: span.location - cursor)
                parts.append(RenderedPart(text: source.substring(with: typed), kind: .text))
            }
            parts.append(RenderedPart(text: span.person.rendered(for: target),
                                      kind: span.person.hasAccount(on: target) ? .mention : .fallback))
            cursor = NSMaxRange(span.range)
        }
        if cursor < source.length {
            parts.append(RenderedPart(text: source.substring(from: cursor), kind: .text))
        }
        return parts
    }
}

/// A run of a post as one network receives it: typed text, a mention in that
/// network's form, or a mention that network gets as plain text.
struct RenderedPart: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        case mention
        case fallback
    }

    let text: String
    let kind: Kind
}
