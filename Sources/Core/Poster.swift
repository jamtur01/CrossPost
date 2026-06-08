import Foundation

/// One published post's user-facing reference.
struct PostedItem: Equatable, Sendable {
    let url: String?
    init(url: String?) { self.url = url }
}

/// Thrown when a thread fails partway through; carries what already landed.
struct ThreadPostError: Error {
    let posted: [PostedItem]
    let failedIndex: Int
    let underlying: Error

    init(posted: [PostedItem], failedIndex: Int, underlying: Error) {
        self.posted = posted
        self.failedIndex = failedIndex
        self.underlying = underlying
    }
}

/// Publishes a whole thread to one target. Throws `ThreadPostError` on mid-thread failure.
protocol Poster: Sendable {
    var target: PostTarget { get }
    func post(thread: [DraftPost]) async throws -> [PostedItem]
}
