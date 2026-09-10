import Foundation

/// Mastodon post visibility. Bluesky has no per-post visibility, so posters and
/// feed services for that platform ignore it. Raw values match Mastodon's API
/// strings so they map straight onto the SDK's visibility type.
enum PostVisibility: String, CaseIterable, Codable, Sendable, Identifiable {
    case `public`
    case unlisted
    case `private`
    case direct

    var id: String {
        rawValue
    }

    /// The visibility of an existing Mastodon post, used to seed a reply so it
    /// never widens the parent's audience. Unknown strings fall back to nil.
    init?(mastodon raw: String?) {
        guard let raw, let value = PostVisibility(rawValue: raw) else { return nil }
        self = value
    }

    var title: String {
        switch self {
        case .public: "Public"
        case .unlisted: "Unlisted"
        case .private: "Followers only"
        case .direct: "Mentioned only"
        }
    }

    /// SF Symbol matching the feed's visibility badge.
    var symbol: String {
        switch self {
        case .public: "globe"
        case .unlisted: "moon"
        case .private: "lock.fill"
        case .direct: "envelope.fill"
        }
    }

    var detail: String {
        switch self {
        case .public: "Visible to everyone, shown in public timelines"
        case .unlisted: "Visible to everyone, hidden from public timelines"
        case .private: "Visible to your followers only"
        case .direct: "Visible only to mentioned people"
        }
    }
}
