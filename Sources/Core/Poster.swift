import Foundation

/// One published post's user-facing reference.
public struct PostedItem: Equatable, Sendable {
    public let url: String?
    public init(url: String?) { self.url = url }
}

/// Thrown when a thread fails partway through; carries what already landed.
public struct ThreadPostError: Error {
    public let posted: [PostedItem]
    public let failedIndex: Int
    public let underlying: Error

    public init(posted: [PostedItem], failedIndex: Int, underlying: Error) {
        self.posted = posted
        self.failedIndex = failedIndex
        self.underlying = underlying
    }
}

/// Publishes a whole thread to one target. Throws `ThreadPostError` on mid-thread failure.
public protocol Poster: Sendable {
    var target: PostTarget { get }
    func post(thread: [DraftPost]) async throws -> [PostedItem]
}
