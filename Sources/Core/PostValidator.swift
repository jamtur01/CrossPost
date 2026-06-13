import Foundation

enum ValidationIssue: Equatable, Sendable {
    case empty(postIndex: Int)
    case tooLong(postIndex: Int, target: PostTarget, count: Int, limit: Int)
    case tooLongBytes(postIndex: Int, target: PostTarget, count: Int, limit: Int)
    case tooManyImages(postIndex: Int, target: PostTarget, count: Int, limit: Int)
    case altTextTooLong(postIndex: Int, imageIndex: Int, target: PostTarget, count: Int, limit: Int)
}

enum MediaValidationError: Error, LocalizedError, Sendable {
    case tooManyImages(target: PostTarget, count: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .tooManyImages(let target, let count, let limit):
            return "\(target.displayName) supports at most \(limit) images per post; \(count) were attached."
        }
    }
}

enum PostValidator {
    /// Grapheme-cluster count. Swift's `String.count` counts Characters (grapheme clusters),
    /// which is the unit Bluesky uses for its 300 limit.
    static func graphemeCount(_ text: String) -> Int {
        text.count
    }

    static func validate(thread: [DraftPost],
                                targets: [PostTarget],
                                limits: TargetLimits) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for (index, post) in thread.enumerated() {
            if post.isEmpty {
                issues.append(.empty(postIndex: index))
                continue
            }
            let count = graphemeCount(post.text)
            let byteCount = post.text.utf8.count
            for target in targets {
                if let limit = limits.maxGraphemes[target], count > limit {
                    issues.append(.tooLong(postIndex: index, target: target, count: count, limit: limit))
                } else if let byteLimit = limits.maxBytes[target], byteCount > byteLimit {
                    // Multi-byte text (emoji, CJK) can blow the byte ceiling while
                    // still under the grapheme limit.
                    issues.append(.tooLongBytes(postIndex: index, target: target,
                                                count: byteCount, limit: byteLimit))
                }
                if let imageLimit = limits.maxImages[target],
                   post.attachments.count > imageLimit {
                    issues.append(.tooManyImages(postIndex: index,
                                                 target: target,
                                                 count: post.attachments.count,
                                                 limit: imageLimit))
                }
                if let altLimit = limits.maxAltText[target] {
                    // Overlong alt text is rejected by the server mid-upload, after
                    // earlier thread posts have already landed — catch it up front.
                    for (imageIndex, attachment) in post.attachments.enumerated() {
                        let altCount = graphemeCount(attachment.altText)
                        guard altCount > altLimit else { continue }
                        issues.append(.altTextTooLong(postIndex: index, imageIndex: imageIndex,
                                                      target: target, count: altCount, limit: altLimit))
                    }
                }
            }
        }
        return issues
    }
}
