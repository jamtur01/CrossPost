import Foundation

enum FeedMerge {
    /// Reconcile a refreshed page with the existing timeline. Fetched posts are the
    /// current server state and keep fetched order; existing posts that are not in
    /// the fetched page stay below them. IDs in `preservingIDs` keep their local
    /// copy so an in-flight optimistic action is not clobbered.
    static func merge(existing: [FeedPost],
                             fetched: [FeedPost],
                             maxCount: Int = 200,
                             preservingIDs: Set<String> = []) -> [FeedPost] {
        var existingByID: [String: FeedPost] = [:]
        for post in existing { existingByID[post.id] = post }
        let fetchedIDs = Set(fetched.map(\.id))
        let reconciled = fetched.map { post in
            if preservingIDs.contains(post.id), let local = existingByID[post.id] {
                return local
            }
            return post
        }
        let retainedExisting = existing.filter { !fetchedIDs.contains($0.id) }
        // Keep-first dedupe so a feed that returns the same id twice (e.g. a status in
        // two mention notifications) can't produce colliding ForEach ids downstream.
        var seen: Set<String> = []
        var unique: [FeedPost] = []
        for post in reconciled + retainedExisting where seen.insert(post.id).inserted {
            unique.append(post)
        }
        return Array(unique.prefix(maxCount))
    }
}
