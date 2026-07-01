import Foundation

/// Fetch up to ~`target` items by following a cursor a few pages deep, stopping at
/// `maxPages`, an empty page, or a nil next cursor. Generic over the cursor type so
/// both platforms share one loop: Mastodon passes a `PagedInfo?` cursor, Bluesky a
/// `String?`. Each `fetch` returns its page plus the cursor for the next one.
func paged<Item, Cursor>(
    target: Int,
    maxPages: Int,
    _ fetch: (Cursor?) async throws -> (items: [Item], cursor: Cursor?)
) async throws -> [Item] {
    var collected: [Item] = []
    var cursor: Cursor?
    for _ in 0..<maxPages {
        let (items, next) = try await fetch(cursor)
        collected += items
        guard collected.count < target, !items.isEmpty, let next else { break }
        cursor = next
    }
    return collected
}
