import Foundation

/// The Home timeline's "N new posts" count: posts a load put above the reader while
/// they were scrolled away from the top, less the ones they have since scrolled up to.
@MainActor
extension FeedPanelModel {
    var newPostCount: Int {
        newPostIDs.count
    }

    /// Records where the reader is in Home. `topPostID` is the post at the top of the
    /// viewport; nil, or an id that isn't a post, means the reader is at the top.
    func homeScrolled(to topPostID: String?) {
        let index = topPostID.flatMap { id in posts.firstIndex { $0.id == id } }
        readingPostID = index == nil ? nil : topPostID
        guard !newPostIDs.isEmpty else { return }
        let above = index.map { Set(posts[..<$0].map(\.id)) } ?? []
        let unseen = newPostIDs.intersection(above)
        if unseen != newPostIDs {
            newPostIDs = unseen
        }
    }

    /// Scrolls the list to the top and clears the count: the pill and user refreshes.
    func scrollToTop() {
        clearNewPosts()
        scrollToTopToken += 1
    }

    func clearNewPosts() {
        readingPostID = nil
        if !newPostIDs.isEmpty {
            newPostIDs = []
        }
    }

    /// Recounts against `next`: the posts above the reader's top post that are new to
    /// the timeline or were already counted. Nothing counts while the reader is at the top.
    func countArrivals(in next: [FeedPost]) {
        var unseen: Set<String> = []
        if readingPostID != nil {
            readingPostID = anchor(in: next)
            if let readingPostID, let index = next.firstIndex(where: { $0.id == readingPostID }) {
                let current = Set(posts.map(\.id))
                for post in next[..<index] where newPostIDs.contains(post.id) || !current.contains(post.id) {
                    unseen.insert(post.id)
                }
            } else {
                // Nothing the reader had is left: the refresh replaced the whole window.
                // It's all new, and the reader sits at its last post until the list
                // reports where they are, so everything above that post counts.
                readingPostID = next.last?.id
                unseen = Set(next.dropLast().map(\.id))
            }
        }
        if unseen != newPostIDs {
            newPostIDs = unseen
        }
    }

    /// The reader's top post in `next`. When it has left (pushed out of the kept window
    /// by arrivals, or deleted), the nearest post that's still kept stands in, above it
    /// first, so arrivals keep counting. Nil when no post the reader had is left.
    private func anchor(in next: [FeedPost]) -> String? {
        guard let readingPostID, let old = posts.firstIndex(where: { $0.id == readingPostID }) else { return nil }
        let kept = Set(next.map(\.id))
        if kept.contains(readingPostID) {
            return readingPostID
        }
        return (posts[..<old].last { kept.contains($0.id) } ?? posts[old...].first { kept.contains($0.id) })?.id
    }
}
