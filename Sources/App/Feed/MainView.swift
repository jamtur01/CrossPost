import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var store: AccountStore
    // Built once in onAppear (they need `store`, unavailable at init) and held here
    // so re-rendering MainView never allocates a fresh model or drops feed state.
    @State private var mastodon: FeedPanelModel?
    @State private var bluesky: FeedPanelModel?
    @State private var lightbox = ImageLightbox()

    var body: some View {
        HSplitView {
            ComposeColumnView()
                .environmentObject(store)
                .frame(minWidth: 240, idealWidth: 320, maxWidth: 380)

            // The two feeds share the remaining space equally (each maxWidth:
            // .infinity), so they are always exactly the same size.
            HStack(spacing: 0) {
                feedColumn(mastodon)
                Divider()
                feedColumn(bluesky)
            }
            .frame(minWidth: 480)
        }
        .frame(minWidth: 760, minHeight: 540)
        .environment(lightbox)
        .overlay { ImageLightboxOverlay(lightbox: lightbox) }
        .onAppear {
            if mastodon == nil { mastodon = FeedPanelModel(target: .mastodon, store: store) }
            if bluesky == nil { bluesky = FeedPanelModel(target: .bluesky, store: store) }
            updateDockBadge()
        }
        .onDisappear { NSApplication.shared.dockTile.badgeLabel = nil }
        // Mirror the total unread notifications (both networks) onto the dock badge.
        .onChange(of: mastodon?.unreadCount) { updateDockBadge() }
        .onChange(of: bluesky?.unreadCount) { updateDockBadge() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .refreshAllFeeds, object: nil)
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .help("Refresh both feeds (⌘R)")
                .keyboardShortcut("r", modifiers: .command)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
    }

    private func updateDockBadge() {
        let total = (mastodon?.unreadCount ?? 0) + (bluesky?.unreadCount ?? 0)
        NSApplication.shared.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
    }

    @ViewBuilder
    private func feedColumn(_ model: FeedPanelModel?) -> some View {
        if let model {
            FeedPanelView(model: model)
                .environmentObject(store)
                .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}

extension Notification.Name {
    /// Posted by the toolbar to refresh every feed panel at once.
    static let refreshAllFeeds = Notification.Name("refreshAllFeeds")
    /// Posted by the View menu to switch both feeds' tab; userInfo carries the FeedKind.
    static let switchFeedKind = Notification.Name("switchFeedKind")
}

/// userInfo key carrying the target `FeedKind` for `switchFeedKind`.
let feedKindKey = "feedKind"
