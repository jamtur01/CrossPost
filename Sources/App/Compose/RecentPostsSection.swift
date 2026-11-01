import AppKit
import SwiftUI

/// The composer's idle-state list of posts CrossPost sent, with each network's
/// reply, repost, and like counts. Counts load when the section appears and on
/// Refresh All; a network's counts open that copy's thread in its own column. Only
/// the signed-in accounts' sends are listed, re-read when credentials change.
struct RecentPostsSection: View {
    let history: SentHistoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Posts")
                .font(Theme.sectionHeader)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            if let problem = history.problem {
                problemNotice(problem)
            }
            if !history.visiblePosts.isEmpty {
                rows
            } else if history.problem == nil {
                Text("Posts you send from CrossPost appear here.")
                    .font(Theme.timelineMeta)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
        .onAppear { history.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .refreshAllFeeds)) { _ in
            history.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .crossPostCredentialsChanged)) { _ in
            // Next turn of the run loop, after the shared feed services for the old
            // account have been dropped.
            Task { history.refresh() }
        }
    }

    private func problemNotice(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(Theme.timelineMeta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show History File") {
                NSWorkspace.shared.activateFileViewerSelecting([history.fileURL])
            }
            .buttonStyle(.link)
            .font(Theme.timelineMeta)
        }
        .padding(.horizontal, 4)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(history.visiblePosts.enumerated()), id: \.element.id) { index, post in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 0.75)
                        .padding(.horizontal, 12)
                }
                RecentPostRow(post: post, history: history)
            }
        }
        .cardSurface()
    }
}

private struct RecentPostRow: View {
    let post: SentPost
    let history: SentHistoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.componentSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(post.text.isEmpty ? "Images only" : post.text)
                    .readingFont(size: 14)
                    .foregroundStyle(post.text.isEmpty ? .secondary : .primary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    if post.publishedCount > 1 {
                        Text("Thread · \(post.publishedCount) posts · ")
                            .font(Theme.timelineMeta)
                            .foregroundStyle(.secondary)
                    }
                    relativeTimestamp(post.date, font: Theme.timelineMeta)
                }
            }
            .accessibilityElement(children: .combine)

            let groups = PostTarget.allCases.compactMap { target in
                post.copy(on: target).flatMap { copy in
                    history.state(of: copy).map { (copy, $0) }
                }
            }
            if !groups.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { networkGroups(groups) }
                    VStack(alignment: .leading, spacing: 2) { networkGroups(groups) }
                }
                .padding(.leading, -NetworkCounts.inset)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, Theme.timelineRowPaddingV)
        .accessibilityElement(children: .contain)
    }

    private func networkGroups(_ groups: [(SentCopy, SentHistoryModel.CopyState)]) -> some View {
        ForEach(groups, id: \.0.target) { copy, state in
            NetworkCounts(target: copy.target, state: state,
                          shortfall: copy.postCount < post.postCount
                              ? "\(copy.postCount) of \(post.postCount) posts" : nil)
        }
    }
}

/// One network's standing for a sent post: its counts as a button that opens the
/// thread in that network's column, or a short status when there's nothing to open.
private struct NetworkCounts: View {
    static let inset: CGFloat = 6
    let target: PostTarget
    let state: SentHistoryModel.CopyState
    /// Set when the thread stopped partway on this network, e.g. "1 of 4 posts".
    let shortfall: String?
    @State private var hovering = false

    var body: some View {
        switch state {
        case let .status(.found(post)):
            Button { open(post) } label: {
                marked { counts(post) }
                    .background(Capsule(style: .continuous).fill(hovering ? Theme.hoverFill : .clear))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Open on \(target.displayName)")
            .accessibilityLabel("Open on \(target.displayName)")
            .accessibilityValue([countsDescription(post), shortfall].compactMap(\.self).joined(separator: ". "))
        case .loading:
            marked {
                RoundedRectangle(cornerRadius: Theme.skeletonCorner, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 92, height: 9)
                    .loadingSheen()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(["\(target.displayName): loading", shortfall].compactMap(\.self)
                .joined(separator: ". "))
        case let .unreachable(message):
            status("—", accessibility: "unavailable. \(message)")
                .help("Couldn't load \(target.displayName): \(message)")
        case .status(.deleted):
            status("Deleted")
        case .status(.olderThanRecent):
            status("Older than your recent posts")
        case .status(.notYetVisible):
            status("Just posted")
        }
    }

    /// The network glyph in its accent, the group's content, then any shortfall.
    private func marked(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 7) {
            Image(systemName: target.glyph)
                .font(.system(size: 12))
                .foregroundStyle(target.accent)
                .accessibilityHidden(true)
            content()
            if let shortfall {
                Text("· \(shortfall)")
                    .font(Theme.timelineMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 4)
    }

    private func counts(_ post: FeedPost) -> some View {
        HStack(spacing: 10) {
            count("bubble", post.replyCount)
            count("arrow.2.squarepath", post.repostCount)
            count("heart", post.likeCount)
        }
        .foregroundStyle(.secondary)
    }

    private func count(_ symbol: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(value.formatted(.number.notation(.compactName))).font(Theme.count)
        }
    }

    private func status(_ text: String, accessibility: String? = nil) -> some View {
        marked {
            Text(text)
                .font(Theme.timelineMeta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["\(target.displayName): \(accessibility ?? text)", shortfall]
            .compactMap(\.self).joined(separator: ". "))
    }

    private func countsDescription(_ post: FeedPost) -> String {
        [
            plural(post.replyCount, "reply", "replies"),
            plural(post.repostCount, "repost", "reposts"),
            plural(post.likeCount, "like", "likes")
        ].joined(separator: ", ")
    }

    private func plural(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }

    private func open(_ post: FeedPost) {
        NotificationCenter.default.post(name: .openFeedPost, object: nil, userInfo: [feedPostKey: post])
    }
}

extension Notification.Name {
    /// Asks the feed column for the post's network to open its thread; userInfo
    /// carries the `FeedPost` under `feedPostKey`.
    static let openFeedPost = Notification.Name("openFeedPost")
}

/// userInfo key carrying the `FeedPost` for `openFeedPost`.
let feedPostKey = "feedPost"
