import SwiftUI

/// The notifications feed: likes, reposts, follows, mentions, replies, quotes.
struct NotificationsListView: View {
    let model: FeedPanelModel
    let push: (FeedRoute) -> Void

    private var accent: Color { model.target.accent }

    var body: some View {
        if model.notifications.isEmpty && model.isLoading {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if model.notifications.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bell").font(.largeTitle).foregroundStyle(.secondary)
                Text("No notifications yet").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.notifications) { notification in
                        NotificationRow(notification: notification, accent: accent, push: push)
                        Divider().opacity(0.5)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct NotificationRow: View {
    let notification: FeedNotification
    let accent: Color
    let push: (FeedRoute) -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        AsyncImage(url: notification.avatarURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(.quaternary)
                        }
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())

                        Text(notification.actorName).font(Theme.name).lineLimit(1)
                        Text(actionText).font(Theme.handle).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(notification.date, format: .relative(presentation: .numeric))
                            .font(Theme.meta).foregroundStyle(.tertiary).fixedSize()
                    }

                    if let post = notification.post, !post.text.characters.isEmpty {
                        Text(post.text)
                            .font(Theme.content)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, Theme.rowPaddingH).padding(.vertical, 10)
            .background(hovering ? Theme.hoverFill : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func open() {
        if let post = notification.post {
            push(.thread(post))
        } else {
            push(.profile(ProfileRef(id: notification.actorID, handle: notification.actorHandle,
                                     name: notification.actorName, avatar: notification.avatarURL)))
        }
    }

    private var icon: String {
        switch notification.kind {
        case .like: return "heart.fill"
        case .repost: return "arrow.2.squarepath"
        case .follow: return "person.fill.badge.plus"
        case .mention: return "at"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .quote: return "quote.bubble.fill"
        case .poll: return "chart.bar.fill"
        case .other: return "bell.fill"
        }
    }

    private var tint: Color {
        switch notification.kind {
        case .like: return .pink
        case .repost: return .green
        default: return accent
        }
    }

    private var actionText: String {
        switch notification.kind {
        case .like: return "liked your post"
        case .repost: return "reposted your post"
        case .follow: return "followed you"
        case .mention: return "mentioned you"
        case .reply: return "replied"
        case .quote: return "quoted your post"
        case .poll: return "a poll ended"
        case .other: return ""
        }
    }
}
