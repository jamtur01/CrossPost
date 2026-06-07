import Foundation

/// A direct-message conversation, projected to the other participant plus a preview.
public struct Conversation: Identifiable, Sendable, Equatable {
    public let id: String
    public let otherName: String
    public let otherHandle: String
    public let otherID: String
    public let otherAvatarURL: URL?
    public let lastMessage: String?
    public let lastDate: Date?
    public let unreadCount: Int

    public init(id: String, otherName: String, otherHandle: String, otherID: String,
                otherAvatarURL: URL?, lastMessage: String?, lastDate: Date?, unreadCount: Int) {
        self.id = id
        self.otherName = otherName
        self.otherHandle = otherHandle
        self.otherID = otherID
        self.otherAvatarURL = otherAvatarURL
        self.lastMessage = lastMessage
        self.lastDate = lastDate
        self.unreadCount = unreadCount
    }
}

/// A single message within a conversation.
public struct DirectMessage: Identifiable, Sendable, Equatable {
    public let id: String
    public let text: String
    public let date: Date
    public let isFromMe: Bool

    public init(id: String, text: String, date: Date, isFromMe: Bool) {
        self.id = id
        self.text = text
        self.date = date
        self.isFromMe = isFromMe
    }
}
