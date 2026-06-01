import Foundation

public struct Attachment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var imageData: Data
    public var altText: String

    public init(id: UUID = UUID(), imageData: Data, altText: String = "") {
        self.id = id
        self.imageData = imageData
        self.altText = altText
    }
}

public struct DraftPost: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var attachments: [Attachment]

    public init(id: UUID = UUID(), text: String = "", attachments: [Attachment] = []) {
        self.id = id
        self.text = text
        self.attachments = attachments
    }

    /// True when there is nothing to post: no text (after trimming) and no images.
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}
