import Sparkle
import SwiftUI

@main
struct CrossPostApp: App {
    @StateObject private var store = AccountStore()
    @AppStorage("showComposer", store: AccountStore.defaults) private var showComposer = true
    private let updater = SPUStandardUpdaterController(
        startingUpdater: !ProcessInfo.processInfo.isRunningTests, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        Window("CrossPost", id: "main") {
            MainView().environmentObject(store)
        }
        .defaultSize(width: 1480, height: 880)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater.updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Post") {
                    NotificationCenter.default.post(name: .focusComposer, object: nil)
                }
                .keyboardShortcut(.newPost)
            }
            CommandGroup(after: .toolbar) {
                Button(showComposer ? "Hide Composer" : "Show Composer") { showComposer.toggle() }
                    .keyboardShortcut(.toggleComposer)
                Divider()
                Button("Refresh All Feeds") {
                    NotificationCenter.default.post(name: .refreshAllFeeds, object: nil)
                }
                .keyboardShortcut(.refreshAll)
                Divider()
                Button("Home") { switchFeeds(.home) }
                    .keyboardShortcut(.showHome)
                Button("Notifications") { switchFeeds(.notifications) }
                    .keyboardShortcut(.showNotifications)
                Button("Messages") { switchFeeds(.messages) }
                    .keyboardShortcut(.showMessages)
            }
            FeedCommands()
            CommandGroup(after: .help) {
                KeyboardShortcutsButton()
            }
        }

        // Opened from Help › Keyboard Shortcuts, so it stays out of the Window menu.
        Window("Keyboard Shortcuts", id: KeyboardShortcutsView.windowID) {
            KeyboardShortcutsView()
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Settings {
            SettingsView().environmentObject(store)
        }
    }

    private func switchFeeds(_ kind: FeedKind) {
        NotificationCenter.default.post(name: .switchFeedKind, object: nil,
                                        userInfo: [feedKindKey: kind])
    }
}
