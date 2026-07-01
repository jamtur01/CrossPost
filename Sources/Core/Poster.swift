import Foundation

/// One published post's user-facing reference plus the native handle needed to
/// continue a thread from it (resume an interrupted cross-post without re-sending
/// what already landed).
struct PostedItem: Equatable, Sendable {
    let url: String?
    let ref: NativeRef?
    init(url: String?, ref: NativeRef? = nil) {
        self.url = url
        self.ref = ref
    }
}

/// Thrown when a thread fails partway through; carries what already landed.
struct ThreadPostError: Error, CustomStringConvertible, LocalizedError {
    let posted: [PostedItem]
    let failedIndex: Int
    let underlying: Error

    init(posted: [PostedItem], failedIndex: Int, underlying: Error) {
        self.posted = posted
        self.failedIndex = failedIndex
        self.underlying = underlying
    }

    var description: String { underlying.userMessage }
    var errorDescription: String? { description }
}

/// Publishes a whole thread to one target. Throws `ThreadPostError` on mid-thread failure.
/// `continuingFrom` resumes an interrupted thread: the given posts are published as a
/// continuation of an already-landed post rather than a fresh thread.
protocol Poster: Sendable {
    var target: PostTarget { get }
    func post(thread: [DraftPost], continuingFrom ref: NativeRef?) async throws -> [PostedItem]
}
