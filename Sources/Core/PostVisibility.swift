import Foundation

/// Mastodon post visibility. Bluesky has no per-post visibility, so posters and
/// feed services for that platform ignore it. Raw values match Mastodon's API
/// strings so they map straight onto the SDK's visibility type.
enum PostVisibility: String, CaseIterable, Sendable, Identifiable {
    case `public`
    case unlisted
    case `private`
    case direct

    var id: String { rawValue }

    /// The visibility of an existing Mastodon post, used to seed a reply so it
    /// never widens the parent's audience. Unknown strings fall back to nil.
    init?(mastodon raw: String?) {
        guard let raw, let value = PostVisibility(rawValue: raw) else { return nil }
        self = value
    }

    var title: String {
        switch self {
        case .public: return "Public"
        case .unlisted: return "Unlisted"
        case .private: return "Followers only"
        case .direct: return "Mentioned only"
        }
    }

    /// SF Symbol matching the feed's visibility badge.
    var symbol: String {
        switch self {
        case .public: return "globe"
        case .unlisted: return "moon"
        case .private: return "lock.fill"
        case .direct: return "envelope.fill"
        }
    }

    var detail: String {
        switch self {
        case .public: return "Visible to everyone, shown in public timelines"
        case .unlisted: return "Visible to everyone, hidden from public timelines"
        case .private: return "Visible to your followers only"
        case .direct: return "Visible only to mentioned people"
        }
    }
}
