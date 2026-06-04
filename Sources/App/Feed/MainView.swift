import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: AccountStore

    var body: some View {
        HSplitView {
            ComposeColumnView()
                .environmentObject(store)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)

            FeedPanelView(model: FeedPanelModel(target: .mastodon, store: store))
                .environmentObject(store)
                .frame(minWidth: 340)

            FeedPanelView(model: FeedPanelModel(target: .bluesky, store: store))
                .environmentObject(store)
                .frame(minWidth: 340)
        }
        .frame(minWidth: 1000, minHeight: 580)
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
