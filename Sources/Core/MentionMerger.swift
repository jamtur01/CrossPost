import Foundation

/// One account returned by a network's mention search.
struct MentionCandidate: Equatable, Sendable {
    let target: PostTarget
    /// Mastodon acct or Bluesky handle, without a leading `@`.
    let handle: String
    let displayName: String
    let avatarURL: URL?
    /// Bio plus profile field values (Mastodon); empty for Bluesky typeahead results.
    let profileText: String
}

/// A Mastodon and a Bluesky account the user said are the same person.
struct MentionPair: Codable, Equatable, Sendable {
    let mastodonAcct: String
    let blueskyHandle: String

    func matches(mastodonAcct acct: String) -> Bool {
        mastodonAcct.caseInsensitiveCompare(acct) == .orderedSame
    }

    func matches(blueskyHandle handle: String) -> Bool {
        blueskyHandle.caseInsensitiveCompare(handle) == .orderedSame
    }
}

/// Combines one search's Mastodon and Bluesky results into people. Two accounts
/// merge only on evidence: a profile pointing at the other account, a Bridgy Fed
/// bridge address, or a saved pair. Matching names alone never merge.
enum MentionMerger {
    static func merge(mastodon: [MentionCandidate], bluesky: [MentionCandidate],
                      pairs: [MentionPair]) -> [MentionPerson] {
        var unmatched = bluesky
        var mastodonPeople: [MentionPerson] = []
        for candidate in mastodon {
            var person = MentionPerson(mastodonAcct: candidate.handle, displayName: candidate.displayName,
                                       avatarURL: candidate.avatarURL)
            if let index = unmatched.firstIndex(where: { sameAccount(candidate, $0, pairs) }) {
                person.blueskyHandle = unmatched.remove(at: index).handle
            }
            mastodonPeople.append(person)
        }
        let blueskyPeople = unmatched.map {
            MentionPerson(blueskyHandle: $0.handle, displayName: $0.displayName, avatarURL: $0.avatarURL)
        }
        return interleave(mastodonPeople, blueskyPeople).map { completed($0, pairs) }
    }

    private static func sameAccount(_ mastodon: MentionCandidate, _ bluesky: MentionCandidate,
                                    _ pairs: [MentionPair]) -> Bool {
        let acct = mastodon.handle.lowercased()
        let handle = bluesky.handle.lowercased()
        if pairs.contains(where: { $0.matches(mastodonAcct: acct) && $0.matches(blueskyHandle: handle) }) {
            return true
        }
        if acct == "\(handle)@bsky.brid.gy" {
            return true
        }
        let parts = acct.split(separator: "@")
        if parts.count == 2, handle == "\(parts[0]).\(parts[1]).ap.brid.gy" {
            return true
        }
        let profile = mastodon.profileText.lowercased()
        return containsHandle(profile, "bsky.app/profile/\(handle)") || containsHandle(profile, "@\(handle)")
    }

    /// True when `needle` occurs in `text` and isn't the start of a longer handle.
    private static func containsHandle(_ text: String, _ needle: String) -> Bool {
        var searchRange = text.startIndex ..< text.endIndex
        while let found = text.range(of: needle, range: searchRange) {
            if !continuesHandle(text[found.upperBound...]) {
                return true
            }
            searchRange = found.upperBound ..< text.endIndex
        }
        return false
    }

    /// Whether `rest` carries on the handle just matched: another handle
    /// character, or a dot that starts a further domain label
    /// (`alice.example.com` inside `alice.example.com.au`). A dot ending a
    /// sentence doesn't.
    private static func continuesHandle(_ rest: Substring) -> Bool {
        guard let next = rest.first else { return false }
        if next == "." {
            return rest.dropFirst().first.map(isHandleCharacter) ?? false
        }
        return isHandleCharacter(next)
    }

    private static func isHandleCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-"
    }

    private static func interleave(_ first: [MentionPerson], _ second: [MentionPerson]) -> [MentionPerson] {
        var result: [MentionPerson] = []
        for index in 0 ..< max(first.count, second.count) {
            if index < first.count {
                result.append(first[index])
            }
            if index < second.count {
                result.append(second[index])
            }
        }
        return result
    }

    /// Fills a single-network person's other account from a saved pair.
    private static func completed(_ person: MentionPerson, _ pairs: [MentionPair]) -> MentionPerson {
        var person = person
        if person.blueskyHandle == nil, let acct = person.mastodonAcct {
            person.blueskyHandle = pairs.first { $0.matches(mastodonAcct: acct) }?.blueskyHandle
        } else if person.mastodonAcct == nil, let handle = person.blueskyHandle {
            person.mastodonAcct = pairs.first { $0.matches(blueskyHandle: handle) }?.mastodonAcct
        }
        return person
    }
}
