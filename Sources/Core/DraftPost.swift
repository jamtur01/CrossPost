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
    /// network's form. Spans are applied last to first so earlier offsets hold;
    /// a span outside the text is left as typed.
    func rendered(for target: PostTarget) -> DraftPost {
        var copy = self
        copy.mentions = []
        guard !mentions.isEmpty else { return copy }
        let output = NSMutableString(string: text)
        for span in mentions.sorted(by: { $0.location > $1.location })
            where span.location >= 0 && NSMaxRange(span.range) <= output.length {
            output.replaceCharacters(in: span.range, with: span.person.rendered(for: target))
        }
        copy.text = output as String
        return copy
    }
}
