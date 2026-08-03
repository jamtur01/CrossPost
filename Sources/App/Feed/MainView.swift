import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var store: AccountStore
    // Built once in onAppear (they need `store`, unavailable at init) and held here
    // so re-rendering MainView never allocates a fresh model or drops feed state.
    @State private var mastodon: FeedPanelModel?
    @State private var bluesky: FeedPanelModel?
    @State private var lightbox = ImageLightbox()
    @State private var relativeTimestampNow = Date()

    var body: some View {
        HSplitView {
            // Keep the authoring surface useful on launch. The previous 240pt
            // floor let the feed group consume surplus width and squash Compose.
            ComposeColumnView()
                .environmentObject(store)
                .frame(minWidth: 390, idealWidth: 400, maxWidth: 480)

            // The two feeds share the remaining space equally (each maxWidth:
            // .infinity), so they are always exactly the same size.
            HStack(spacing: 0) {
                feedColumn(mastodon)
                Divider()
                feedColumn(bluesky)
            }
            // Each feed stays legible: ~290pt min per column side-by-side.
            .frame(minWidth: 580)
        }
        .frame(minWidth: 980, minHeight: 560)
        .environment(lightbox)
        .environment(\.relativeTimestampNow, relativeTimestampNow)
        .overlay { ImageLightboxOverlay(lightbox: lightbox) }
        .onAppear {
            if mastodon == nil { mastodon = FeedPanelModel(target: .mastodon, store: store) }
            if bluesky == nil { bluesky = FeedPanelModel(target: .bluesky, store: store) }
            updateDockBadge()
        }
        .onDisappear { NSApplication.shared.dockTile.badgeLabel = nil }
        .task { await runRelativeTimestampClock() }
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

    @MainActor
    private func runRelativeTimestampClock() async {
        relativeTimestampNow = Date()

        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSinceReferenceDate
            let remainder = elapsed.truncatingRemainder(dividingBy: 60)

            do {
                try await ContinuousClock().sleep(for: .seconds(60 - remainder))
            } catch {
                return
            }

            relativeTimestampNow = Date()
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
