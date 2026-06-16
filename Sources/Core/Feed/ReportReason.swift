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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: return "Spam"
        case .harassment: return "Harassment or abuse"
        case .misleading: return "Misleading or false"
        case .sexual: return "Unwanted sexual content"
        case .illegal: return "Illegal content"
        case .other: return "Other"
        }
    }
}
