import Foundation

public enum FeedKind: String, CaseIterable, Sendable, Identifiable {
    case home
    case notifications
    case messages

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .home: return "Home"
        case .notifications: return "Notifications"
        case .messages: return "Messages"
        }
    }
}
