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
    }
}
