import Foundation

enum FeedMerge {
    /// Keep the refreshed page first and retain bounded older history without duplicate IDs.
    static func retainingHistory<Item: Identifiable>(
        existing: [Item], fetched: [Item], maxCount: Int = 200
    ) -> [Item] {
        guard maxCount > 0 else { return [] }
        var seen: Set<Item.ID> = []
        var result: [Item] = []
        for item in fetched + existing where seen.insert(item.id).inserted {
            result.append(item)
            if result.count == maxCount {
                break
            }
        }
        return result
    }

    /// Reconcile a refreshed page with the existing timeline. Fetched posts are the
    /// current server state and keep fetched order; existing posts that are not in
    /// the fetched page stay below them. IDs in `preservingIDs` keep their local
    /// copy so an in-flight optimistic action is not clobbered. IDs in
    /// `excludingIDs` are mid-delete locally: the local row is already gone, so
    /// they are dropped from both lists — otherwise a poll that raced the delete
    /// would resurrect the row from the fetched page.
    static func merge(existing: [FeedPost],
                      fetched: [FeedPost],
                      maxCount: Int = 200,
                      preservingIDs: Set<String> = [],
                      excludingIDs: Set<String> = []) -> [FeedPost] {
        var existingByID: [String: FeedPost] = [:]
        for post in existing {
            existingByID[post.id] = post
        }
        let fetchedIDs = Set(fetched.map(\.id))
        let reconciled = fetched.compactMap { post -> FeedPost? in
            if excludingIDs.contains(post.id) {
                return nil
            }
            if preservingIDs.contains(post.id), let local = existingByID[post.id] {
                return local
            }
            return post
        }
        let retainedExisting = existing.filter {
            !fetchedIDs.contains($0.id) && !excludingIDs.contains($0.id)
        }
        return retainingHistory(existing: retainedExisting, fetched: reconciled, maxCount: maxCount)
    }
}
