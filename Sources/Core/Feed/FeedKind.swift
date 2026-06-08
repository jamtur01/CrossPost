import Foundation

enum FeedKind: String, CaseIterable, Sendable, Identifiable {
    case home
    case notifications
    case messages

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .notifications: return "Notifications"
        case .messages: return "Messages"
        }
    }
}
