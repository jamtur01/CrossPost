import Foundation

enum PostTarget: String, CaseIterable, Codable, Sendable, Identifiable {
    case mastodon
    case bluesky

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .mastodon: "Mastodon"
        case .bluesky: "Bluesky"
        }
    }
}
