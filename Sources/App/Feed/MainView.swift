import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: AccountStore

    var body: some View {
        HSplitView {
            ComposeColumnView()
                .environmentObject(store)
                .frame(minWidth: 240, idealWidth: 320, maxWidth: 380)

            // The two feeds share the remaining space equally (each maxWidth:
            // .infinity), so they are always exactly the same size.
            HStack(spacing: 0) {
                FeedPanelView(model: FeedPanelModel(target: .mastodon, store: store))
                    .environmentObject(store)
                    .frame(maxWidth: .infinity)
                Divider()
                FeedPanelView(model: FeedPanelModel(target: .bluesky, store: store))
                    .environmentObject(store)
                    .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 480)
        }
        .frame(minWidth: 760, minHeight: 540)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .refreshAllFeeds, object: nil)
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .help("Refresh both feeds")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
    }
}

extension Notification.Name {
    /// Posted by the toolbar to refresh every feed panel at once.
    static let refreshAllFeeds = Notification.Name("refreshAllFeeds")
}
