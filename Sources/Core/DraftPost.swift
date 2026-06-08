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

    init(id: UUID = UUID(), text: String = "", attachments: [Attachment] = []) {
        self.id = id
        self.text = text
        self.attachments = attachments
    }

    /// True when there is nothing to post: no text (after trimming) and no images.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}
