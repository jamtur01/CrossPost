import Foundation

public enum ValidationIssue: Equatable, Sendable {
    case empty(postIndex: Int)
    case tooLong(postIndex: Int, target: PostTarget, count: Int, limit: Int)
    case tooManyImages(postIndex: Int, target: PostTarget, count: Int, limit: Int)
}

public enum MediaValidationError: Error, LocalizedError, Sendable {
    case tooManyImages(target: PostTarget, count: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .tooManyImages(let target, let count, let limit):
            return "\(target.displayName) supports at most \(limit) images per post; \(count) were attached."
        }
    }
}

public enum PostValidator {
    /// Grapheme-cluster count. Swift's `String.count` counts Characters (grapheme clusters),
    /// which is the unit Bluesky uses for its 300 limit.
    public static func graphemeCount(_ text: String) -> Int {
        text.count
    }

    public static func validate(thread: [DraftPost],
                                targets: [PostTarget],
                                limits: TargetLimits) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for (index, post) in thread.enumerated() {
            if post.isEmpty {
                issues.append(.empty(postIndex: index))
                continue
            }
            let count = graphemeCount(post.text)
            for target in targets {
                guard let limit = limits.maxGraphemes[target] else { continue }
                if count > limit {
                    issues.append(.tooLong(postIndex: index, target: target, count: count, limit: limit))
                }
                if let imageLimit = limits.maxImages[target],
                   post.attachments.count > imageLimit {
                    issues.append(.tooManyImages(postIndex: index,
                                                 target: target,
                                                 count: post.attachments.count,
                                                 limit: imageLimit))
                }
            }
        }
        return issues
    }
}
