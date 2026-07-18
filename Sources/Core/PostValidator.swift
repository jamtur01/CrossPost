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

    /// Grapheme count as the target's server counts it: Mastodon counts a
    /// "countable" transform of the text, Bluesky counts the raw text.
    static func countedGraphemes(_ text: String, for target: PostTarget) -> Int {
        switch target {
        case .mastodon: return graphemeCount(mastodonCountableText(text))
        case .bluesky: return graphemeCount(text)
        }
    }

    /// Matches http(s) links the way Mastodon linkifies them: scheme required,
    /// running to whitespace, with trailing punctuation left outside the link.
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://\S+"#, options: [.caseInsensitive])

    /// Remote mention `@user@domain`, preceded by start of text or a non-word,
    /// non-slash character so emails (`bob@example.com`) and URL paths are left alone.
    private static let remoteMentionPattern = try! NSRegularExpression(
        pattern: #"(?<![\w/])@([a-zA-Z0-9_]+)@[a-zA-Z0-9.\-]+"#)

    /// Punctuation Mastodon treats as prose after a link, not part of it.
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?…'\")]}")

    /// The text Mastodon's server actually counts (its StatusLengthValidator):
    /// every http(s) link counts as a fixed 23 characters regardless of length,
    /// and a remote mention `@user@example.social` counts as just `@user`.
    /// WHY an approximation: the server linkifies with Twitter's URL regex, which
    /// is enormous; scheme-required links trimmed at whitespace/trailing
    /// punctuation and `@user@domain` mentions cover what people actually post.
    /// Pathological edge cases may count a few characters differently than the
    /// server, but ordinary links and mentions count exactly.
    static func mastodonCountableText(_ text: String) -> String {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let placeholder = String(repeating: "x", count: 23)
        var output = ""
        var cursor = 0
        for match in urlPattern.matches(in: text, range: fullRange) {
            var range = match.range
            while range.length > 0 {
                let last = ns.substring(with: NSRange(location: range.location + range.length - 1,
                                                      length: 1))
                guard last.rangeOfCharacter(from: trailingPunctuation) != nil else { break }
                range.length -= 1
            }
            let matched = ns.substring(with: range)
            // A bare scheme ("https://") isn't a link; count it as itself.
            guard let schemeEnd = matched.range(of: "://"),
                  !matched[schemeEnd.upperBound...].isEmpty else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            output += placeholder
            cursor = range.location + range.length
        }
        output += ns.substring(from: cursor)
        let outputRange = NSRange(location: 0, length: (output as NSString).length)
        return remoteMentionPattern.stringByReplacingMatches(in: output, range: outputRange,
                                                             withTemplate: "@$1")
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
            let byteCount = post.text.utf8.count
            for target in targets {
                let count = countedGraphemes(post.text, for: target)
                if let limit = limits.maxGraphemes[target], count > limit {
                    issues.append(.tooLong(postIndex: index, target: target, count: count, limit: limit))
                } else if let byteLimit = limits.maxBytes[target], byteCount > byteLimit {
                    // Multi-byte text (emoji, CJK) can blow the byte ceiling while
                    // still under the grapheme limit.
                    issues.append(.tooLongBytes(postIndex: index, target: target,
                                                count: byteCount, limit: byteLimit))
                }
                if case .tooManyImages(_, let imageCount, let imageLimit)? =
                        limits.imageCountViolation(count: post.attachments.count, for: target) {
                    issues.append(.tooManyImages(postIndex: index,
                                                 target: target,
                                                 count: imageCount,
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
