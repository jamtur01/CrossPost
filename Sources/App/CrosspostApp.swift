import SwiftUI

@main
struct CrosspostApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        WindowGroup("Crosspost") {
            MainView().environmentObject(store)
        }
        .defaultSize(width: 1180, height: 720)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
