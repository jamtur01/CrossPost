import Combine
import Sparkle
import SwiftUI

/// The "Check for Updates…" menu item, disabled while Sparkle is already
/// checking or installing (or never started, as in the test host).
struct CheckForUpdatesButton: View {
    let updater: SPUUpdater
    @StateObject private var state: UpdaterState

    init(updater: SPUUpdater) {
        self.updater = updater
        _state = StateObject(wrappedValue: UpdaterState(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!state.canCheckForUpdates)
    }
}

@MainActor
private final class UpdaterState: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
}
