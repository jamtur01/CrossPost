import Foundation

/// A person picked from @-mention autocomplete: their account on each network
/// (either may be missing) and the name a network they're not on receives.
struct MentionPerson: Codable, Hashable, Sendable {
    var mastodonAcct: String?
    var blueskyHandle: String?
    var displayName: String
    var avatarURL: URL?

    init(mastodonAcct: String? = nil, blueskyHandle: String? = nil,
         displayName: String, avatarURL: URL? = nil) {
        self.mastodonAcct = mastodonAcct
        self.blueskyHandle = blueskyHandle
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    /// The editor's text for this mention: `@` plus the Mastodon username, else
    /// the Bluesky handle without a `.bsky.social` suffix.
    var visibleText: String {
        if let acct = mastodonAcct {
            return "@" + (acct.split(separator: "@").first.map(String.init) ?? acct)
        }
        let handle = blueskyHandle ?? ""
        let suffix = ".bsky.social"
        return "@" + (handle.hasSuffix(suffix) ? String(handle.dropLast(suffix.count)) : handle)
    }

    func hasAccount(on target: PostTarget) -> Bool {
        (target == .mastodon ? mastodonAcct : blueskyHandle) != nil
    }

    /// What `target` receives in place of the mention: its own handle, else the
    /// display name, else the other network's handle as plain text.
    func rendered(for target: PostTarget) -> String {
        let own = target == .mastodon ? mastodonAcct : blueskyHandle
        if let own {
            return "@" + own
        }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        return (target == .mastodon ? blueskyHandle : mastodonAcct) ?? ""
    }
}

/// A mention in a draft: the UTF-16 range of its visible text and who it names.
struct MentionSpan: Codable, Hashable, Sendable {
    var location: Int
    var length: Int
    var person: MentionPerson

    var range: NSRange {
        NSRange(location: location, length: length)
    }
}

/// The `@` token being typed at the caret: `@` at the start of the text or after
/// whitespace, then at least two non-whitespace characters, ending at the caret.
struct MentionQuery: Equatable, Sendable {
    /// The `@` through the caret, in UTF-16 units.
    let range: NSRange
    /// What follows the `@`.
    let text: String

    static func detect(in text: String, caret: Int) -> MentionQuery? {
        let utf16Text = text as NSString
        guard caret > 0, caret <= utf16Text.length else { return nil }
        if caret < utf16Text.length, !isWhitespace(utf16Text.character(at: caret)) {
            return nil
        }
        var start = caret
        while start > 0, !isWhitespace(utf16Text.character(at: start - 1)) {
            start -= 1
        }
        let token = utf16Text.substring(with: NSRange(location: start, length: caret - start))
        guard token.hasPrefix("@"), token.count >= 3 else { return nil }
        return MentionQuery(range: NSRange(location: start, length: caret - start),
                            text: String(token.dropFirst()))
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
