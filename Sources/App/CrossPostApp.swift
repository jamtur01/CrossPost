import SwiftUI

@main
struct CrossPostApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        WindowGroup("CrossPost") {
            MainView().environmentObject(store)
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh All Feeds") {
                    NotificationCenter.default.post(name: .refreshAllFeeds, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Home") { switchFeeds(.home) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Notifications") { switchFeeds(.notifications) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Messages") { switchFeeds(.messages) }
                    .keyboardShortcut("3", modifiers: .command)
            }
        }

        Settings {
            SettingsView().environmentObject(store)
        }
    }

    private func switchFeeds(_ kind: FeedKind) {
        NotificationCenter.default.post(name: .switchFeedKind, object: nil,
                                        userInfo: [feedKindKey: kind])
    }
}
