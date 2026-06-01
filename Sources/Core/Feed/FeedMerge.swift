import Foundation

public enum FeedMerge {
    /// Prepend genuinely-new fetched posts (in fetched order) ahead of existing
    /// ones. Posts already present keep their position AND their current action
    /// state (so a freshly-fetched page doesn't clobber an optimistic like).
    public static func merge(existing: [FeedPost], fetched: [FeedPost]) -> [FeedPost] {
        let existingIDs = Set(existing.map(\.id))
        let newOnes = fetched.filter { !existingIDs.contains($0.id) }
        return newOnes + existing
    }
}
