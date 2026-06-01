import Foundation

public enum FeedKind: String, CaseIterable, Sendable, Identifiable {
    case home
    case mentions

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .home: return "Home"
        case .mentions: return "Mentions"
        }
    }
}
