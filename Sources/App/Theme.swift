import SwiftUI

extension PostTarget {
    /// Brand accent — Mastodon "Blurple" (#6364FF), Bluesky blue (#0A7AFF).
    var accent: Color {
        switch self {
        case .mastodon: return Color(red: 0.388, green: 0.392, blue: 1.0)
        case .bluesky: return Color(red: 0.039, green: 0.478, blue: 1.0)
        }
    }
}
