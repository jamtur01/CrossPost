import SwiftUI

@main
struct CrosspostApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        WindowGroup("Crosspost") {
            ComposeView().environmentObject(store)
        }
        .defaultSize(width: 560, height: 540)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
