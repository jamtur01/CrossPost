import SwiftUI

@main
struct CrossPostApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        WindowGroup("CrossPost") {
            MainView().environmentObject(store)
        }
        .defaultSize(width: 1180, height: 720)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
