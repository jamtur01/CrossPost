import Foundation

public enum FeedMerge {
    /// Reconcile a refreshed page with the existing timeline. Fetched posts are the
    /// current server state and keep fetched order; existing posts that are not in
    /// the fetched page stay below them. IDs in `preservingIDs` keep their local
    /// copy so an in-flight optimistic action is not clobbered.
    public static func merge(existing: [FeedPost],
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
        return Array((reconciled + retainedExisting).prefix(maxCount))
    }
}
