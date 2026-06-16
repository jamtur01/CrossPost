import Foundation

/// The post id to select for keyboard feed navigation (j/k). With nothing
/// selected, returns the first post; otherwise moves one row and clamps at the
/// ends. Returns nil only for an empty feed.
func feedSelectionID(movingDown: Bool, from current: String?, in posts: [FeedPost]) -> String? {
    guard !posts.isEmpty else { return nil }
    guard let current, let index = posts.firstIndex(where: { $0.id == current }) else {
        return posts.first?.id
    }
    let target = movingDown ? index + 1 : index - 1
    guard posts.indices.contains(target) else { return current }
    return posts[target].id
}
