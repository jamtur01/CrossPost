import Foundation

struct Attachment: Identifiable, Equatable, Sendable {
    let id: UUID
    var imageData: Data
    var altText: String

    init(id: UUID = UUID(), imageData: Data, altText: String = "") {
        self.id = id
        self.imageData = imageData
        self.altText = altText
    }
}

struct DraftPost: Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var attachments: [Attachment]
    /// Mastodon visibility for this post; ignored by Bluesky.
    var visibility: PostVisibility

    init(id: UUID = UUID(), text: String = "", attachments: [Attachment] = [],
         visibility: PostVisibility = .public) {
        self.id = id
        self.text = text
        self.attachments = attachments
        self.visibility = visibility
    }

    /// True when there is nothing to post: no text (after trimming) and no images.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}
