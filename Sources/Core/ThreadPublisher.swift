import Foundation

/// Publishes a single post given the thread's root and the immediate parent.
/// `Ref` is the target's opaque post reference (status id for Mastodon, StrongReference for Bluesky).
public protocol ThreadPublisher: Sendable {
    associatedtype Ref: Sendable
    func publishOne(_ draft: DraftPost, root: Ref?, parent: Ref?) async throws -> (ref: Ref, item: PostedItem)
}

/// Runs a thread sequentially: the first post sets the root; each subsequent post
/// replies to the previous (parent) while keeping the original root.
public func runThread<P: ThreadPublisher>(_ drafts: [DraftPost], using publisher: P) async throws -> [PostedItem] {
    var posted: [PostedItem] = []
    var root: P.Ref?
    var parent: P.Ref?

    for (index, draft) in drafts.enumerated() {
        do {
            let (ref, item) = try await publisher.publishOne(draft, root: root, parent: parent)
            posted.append(item)
            if root == nil { root = ref }
            parent = ref
        } catch {
            throw ThreadPostError(posted: posted, failedIndex: index, underlying: error)
        }
    }
    return posted
}
