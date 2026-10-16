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
}

/// A single message within a conversation.
struct DirectMessage: Identifiable, Sendable, Equatable {
    let id: String
    let text: String
    let date: Date
    let isFromMe: Bool
}
