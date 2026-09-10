import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: AccountStore
    // Built once in onAppear (they need `store`, unavailable at init) and held here
    // so re-rendering MainView never allocates a fresh model or drops feed state.
    @State private var mastodon: FeedPanelModel?
    @State private var bluesky: FeedPanelModel?
    @State private var compose: ComposeModel?
    @AppStorage("showComposer", store: AccountStore.defaults) private var showComposer = true
    @State private var lightbox = ImageLightbox()
    @State private var relativeTimestampNow = Date()

    var body: some View {
        HSplitView {
            if showComposer, let compose {
                ComposeColumnView(model: compose)
                    .environmentObject(store)
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 440)
            }

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
        .frame(minWidth: showComposer ? 920 : 600, minHeight: 560)
        .environment(lightbox)
        .environment(\.relativeTimestampNow, relativeTimestampNow)
        .overlay { ImageLightboxOverlay(lightbox: lightbox) }
        .onAppear {
            if mastodon == nil {
                mastodon = FeedPanelModel(target: .mastodon, store: store)
            }
            if bluesky == nil {
                bluesky = FeedPanelModel(target: .bluesky, store: store)
            }
            if compose == nil {
                compose = ComposeModel(store: store, draftStore: .application)
            }
            updateDockBadge()
        }
        .onDisappear {
            compose?.flushDraft()
            NSApplication.shared.dockTile.badgeLabel = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            compose?.flushDraft()
        }
        .task { await runRelativeTimestampClock() }
        // Mirror the total unread notifications (both networks) onto the dock badge.
        .onChange(of: mastodon?.unreadCount) { updateDockBadge() }
        .onChange(of: bluesky?.unreadCount) { updateDockBadge() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showComposer.toggle() } label: {
                    Label(showComposer ? "Hide Composer" : "Show Composer", systemImage: "sidebar.left")
                }
                .help(showComposer ? "Hide composer (⇧⌘C)" : "Show composer (⇧⌘C)")
                .accessibilityValue(showComposer ? "Visible" : "Hidden")
            }
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
