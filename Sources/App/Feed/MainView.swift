import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: AccountStore

    var body: some View {
        HSplitView {
            ComposeColumnView()
                .environmentObject(store)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            FeedPanelView(model: FeedPanelModel(target: .mastodon, store: store))
                .environmentObject(store)
                .frame(minWidth: 320)

            FeedPanelView(model: FeedPanelModel(target: .bluesky, store: store))
                .environmentObject(store)
                .frame(minWidth: 320)
        }
        .frame(minWidth: 980, minHeight: 560)
    }
}
