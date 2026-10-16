import Foundation

/// A cross-platform moderation report reason. Each adapter maps it onto its
/// platform's own category set.
enum ReportReason: String, CaseIterable, Sendable, Identifiable {
    case spam
    case harassment
    case misleading
    case sexual
    case illegal
    case other

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment or abuse"
        case .misleading: "Misleading or false"
        case .sexual: "Unwanted sexual content"
        case .illegal: "Illegal content"
        case .other: "Other"
        }
    }
}
