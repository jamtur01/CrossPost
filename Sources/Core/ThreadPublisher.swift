import Foundation

/// Publishes a single post given the thread's root and the immediate parent.
/// `Ref` is the target's opaque post reference (status id for Mastodon, StrongReference for Bluesky).
protocol ThreadPublisher: Sendable {
    associatedtype Ref: Sendable
    func publishOne(_ draft: DraftPost, root: Ref?, parent: Ref?) async throws -> (ref: Ref, item: PostedItem)
    /// Reconstruct the (root, parent) refs to continue a thread from an already-landed
    /// post, so an interrupted cross-post resumes instead of re-sending the prefix.
    /// Returns nil if the native ref isn't this platform's.
    func resumeRefs(from ref: NativeRef) -> (root: Ref, parent: Ref)?
}

/// Runs a thread sequentially: the first post sets the root; each subsequent post
/// replies to the previous (parent) while keeping the original root. When
/// `continuingFrom` is given, the drafts continue an already-landed post: its ref
/// seeds root+parent so the first new post replies to it under the original root.
func runThread<P: ThreadPublisher>(_ drafts: [DraftPost], using publisher: P,
                                   continuingFrom resumeRef: NativeRef? = nil) async throws -> [PostedItem] {
    var posted: [PostedItem] = []
    var root: P.Ref?
    var parent: P.Ref?
    if let resumeRef, let refs = publisher.resumeRefs(from: resumeRef) {
        root = refs.root
        parent = refs.parent
    }

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
