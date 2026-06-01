import SwiftUI

@main
struct CrosspostApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        WindowGroup("Crosspost") {
            ComposeView(model: ComposeModel(store: store))
                .environmentObject(store)
        }
        .defaultSize(width: 640, height: 560)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
