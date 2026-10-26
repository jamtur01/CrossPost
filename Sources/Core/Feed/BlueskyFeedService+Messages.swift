import ATProtoKit
import Foundation

// MARK: Direct messages

extension BlueskyFeedService {
    func conversations(includeHistory: Bool,
                       onPage: @Sendable ([Conversation]) async -> Void) async throws -> [Conversation] {
        let myDID = try await ownDID()
        let convos = try await paged(target: 200, maxPages: includeHistory ? 3 : 1, onPage: { convos in
            await onPage(Self.conversations(from: convos, ownDID: myDID))
        }, {
            let output = try await chat.listConversations(limit: 100, cursor: $0)
            return (output.conversations, output.cursor)
        })
        return Self.conversations(from: convos, ownDID: myDID)
    }

    static func conversations(
        from convos: [ChatBskyLexicon.Conversation.ConversationViewDefinition], ownDID: String
    ) -> [Conversation] {
        convos.compactMap { convo in
            // Fall back to the first member for a self-conversation (DM to yourself).
            guard let other = convo.members.first(where: { $0.actorDID != ownDID }) ?? convo.members.first
            else { return nil }
            let last = Self.lastMessage(convo.lastMessage)
            return Conversation(
                id: convo.conversationID,
                otherName: displayOrHandle(other.displayName, other.actorHandle),
                otherHandle: "@\(other.actorHandle)", otherID: other.actorDID,
                otherAvatarURL: other.avatarImageURL,
                lastMessage: last.text, lastDate: last.date, unreadCount: convo.unreadCount
            )
        }
    }

    func messages(in conversationID: String) async throws -> [DirectMessage] {
        let myDID = try await ownDID()
        // ATProtoKit's getMessages exposes no cursor, so fetch its max page (100).
        // Deep DM history beyond one page isn't reachable until the SDK adds a cursor.
        let output = try await chat.getMessages(from: conversationID, limit: 100)
        let messages = output.messages.compactMap { message -> DirectMessage? in
            guard case let .messageView(message) = message else { return nil }
            return DirectMessage(id: message.messageID, text: message.text, date: message.sentAt,
                                 isFromMe: message.sender.authorDID == myDID)
        }
        return messages.reversed() // getMessages returns newest-first; show oldest-first
    }

    func sendMessage(_ text: String, to conversationID: String) async throws {
        _ = try await chat.sendMessage(
            to: conversationID,
            message: ChatBskyLexicon.Conversation.MessageInputDefinition(text: text)
        )
    }

    func conversation(with accountID: String) async throws -> Conversation {
        let myDID = try await ownDID()
        let did = accountID.hasPrefix("did:")
            ? accountID
            : try await kit.resolveHandle(from: accountID.trimmingPrefix("@").description).did
        let output = try await chat.getConversaionForMembers([did])
        guard let convo = Self.conversations(from: [output.conversation], ownDID: myDID).first else {
            throw FeedError.notSupported("Bluesky returned a conversation with no members.")
        }
        return convo
    }
}
