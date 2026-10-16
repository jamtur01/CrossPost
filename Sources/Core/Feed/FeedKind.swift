import Foundation

enum FeedKind: String, CaseIterable, Sendable, Identifiable {
    case home
    case notifications
    case messages

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .notifications: "Notifications"
        case .messages: "Messages"
        }
    }
}
