import Foundation

enum PostTarget: String, CaseIterable, Sendable, Identifiable {
    case mastodon
    case bluesky

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mastodon: return "Mastodon"
        case .bluesky: return "Bluesky"
        }
    }
}
