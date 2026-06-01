import Foundation

public enum PostTarget: String, CaseIterable, Sendable, Identifiable {
    case mastodon
    case bluesky

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mastodon: return "Mastodon"
        case .bluesky: return "Bluesky"
        }
    }
}
