import Foundation

/// A direct-message conversation, projected to the other participant plus a preview.
struct Conversation: Identifiable, Sendable, Equatable {
    let id: String
    let otherName: String
    let otherHandle: String
    let otherID: String
    let otherAvatarURL: URL?
    let lastMessage: String?
    let lastDate: Date?
    var unreadCount: Int

    init(id: String, otherName: String, otherHandle: String, otherID: String,
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
struct DirectMessage: Identifiable, Sendable, Equatable {
    let id: String
    let text: String
    let date: Date
    let isFromMe: Bool

    init(id: String, text: String, date: Date, isFromMe: Bool) {
        self.id = id
        self.text = text
        self.date = date
        self.isFromMe = isFromMe
    }
}
