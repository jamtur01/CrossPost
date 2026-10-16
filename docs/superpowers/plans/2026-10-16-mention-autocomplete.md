# Mention Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Typing `@` in the compose editor searches Mastodon and Bluesky; a picked
person becomes a mention that each network receives in its own form, with a
preview toggle showing each network's final text.

**Architecture:** Core gains a mention model (`MentionPerson`, `MentionSpan`),
per-target rendering on `DraftPost`, query detection, candidate merging and a
JSON pair store; the validator and coordinator render per target. App gains a
`MentionDirectory` (service cache + pairs), a per-editor `MentionCompletion`
state machine, attribute-run tracking in `PlainTextEditor`, a suggestion list in
the post card, a pairing sheet, and a preview picker.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSTextView`), TootSDK, ATProtoKit,
XCTest. Spec: `docs/superpowers/specs/2026-10-16-mention-autocomplete-design.md`.

**Commands:**

- Regenerate project after adding files: `xcodegen generate`
- Run one test class: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' -only-testing:CrossPostTests/<Class> 2>&1 | tail -20`
- Lint: `swiftlint --strict` and `swiftformat --lint .`

---

### Task 1: Mention model and per-target rendering (Core)

**Files:**
- Create: `Sources/Core/Mention.swift`
- Modify: `Sources/Core/DraftPost.swift`
- Test: `Tests/CoreTests/MentionRenderingTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import CrossPost

final class MentionRenderingTests: XCTestCase {
    private let both = MentionPerson(mastodonAcct: "puppetfather@hachyderm.io",
                                     blueskyHandle: "puppetfather.bsky.social",
                                     displayName: "Luke Kanies")

    private func draft(_ text: String, _ person: MentionPerson, at location: Int) -> DraftPost {
        let length = person.visibleText.utf16.count
        return DraftPost(text: text, mentions: [MentionSpan(location: location, length: length, person: person)])
    }

    func testVisibleTextPrefersMastodonUsername() {
        XCTAssertEqual(both.visibleText, "@puppetfather")
        let bluesky = MentionPerson(blueskyHandle: "alice.bsky.social", displayName: "Alice")
        XCTAssertEqual(bluesky.visibleText, "@alice")
        let custom = MentionPerson(blueskyHandle: "jamesturnbull.net", displayName: "James")
        XCTAssertEqual(custom.visibleText, "@jamesturnbull.net")
    }

    func testRendersEachNetworksHandle() {
        let post = draft("Hi @puppetfather!", both, at: 3)
        XCTAssertEqual(post.rendered(for: .mastodon).text, "Hi @puppetfather@hachyderm.io!")
        XCTAssertEqual(post.rendered(for: .bluesky).text, "Hi @puppetfather.bsky.social!")
        XCTAssertEqual(post.rendered(for: .bluesky).mentions, [])
    }

    func testMissingNetworkGetsDisplayNameThenOtherHandle() {
        let mastodonOnly = MentionPerson(mastodonAcct: "bob@example.social", displayName: "Bob")
        XCTAssertEqual(draft("@bob", mastodonOnly, at: 0).rendered(for: .bluesky).text, "Bob")
        let nameless = MentionPerson(mastodonAcct: "bob@example.social", displayName: "  ")
        XCTAssertEqual(draft("@bob", nameless, at: 0).rendered(for: .bluesky).text, "bob@example.social")
        let blueskyOnly = MentionPerson(blueskyHandle: "alice.bsky.social", displayName: "")
        XCTAssertEqual(draft("@alice", blueskyOnly, at: 0).rendered(for: .mastodon).text, "alice.bsky.social")
    }

    func testMultipleMentionsAfterEmojiUseUTF16Offsets() {
        let alice = MentionPerson(blueskyHandle: "alice.bsky.social", displayName: "Alice")
        let text = "👨‍👩‍👧‍👦 @puppetfather and @alice"
        let ns = text as NSString
        let first = ns.range(of: "@puppetfather")
        let second = ns.range(of: "@alice")
        let post = DraftPost(text: text, mentions: [
            MentionSpan(location: first.location, length: first.length, person: both),
            MentionSpan(location: second.location, length: second.length, person: alice),
        ])
        XCTAssertEqual(post.rendered(for: .mastodon).text,
                       "👨‍👩‍👧‍👦 @puppetfather@hachyderm.io and Alice")
        XCTAssertEqual(post.rendered(for: .bluesky).text,
                       "👨‍👩‍👧‍👦 @puppetfather.bsky.social and @alice.bsky.social")
    }

    func testOutOfRangeSpanIsLeftAsTyped() {
        let post = DraftPost(text: "@pup", mentions: [MentionSpan(location: 2, length: 20, person: both)])
        XCTAssertEqual(post.rendered(for: .mastodon).text, "@pup")
    }

    func testSavedDraftWithoutMentionsDecodes() throws {
        let legacy = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"hi","attachments":[],"visibility":"public"}"#
        let post = try JSONDecoder().decode(DraftPost.self, from: Data(legacy.utf8))
        XCTAssertEqual(post.text, "hi")
        XCTAssertEqual(post.mentions, [])
    }
}
```

Check `PostVisibility`'s raw value for `.public` in `Sources/Core/PostVisibility.swift` and match it in the legacy JSON.

- [ ] **Step 2: Run, expect compile failure** (`MentionPerson` undefined).

- [ ] **Step 3: Implement**

`Sources/Core/Mention.swift`:

```swift
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
```

`Sources/Core/DraftPost.swift` — add the field, init parameter, legacy decoding
and rendering:

```swift
struct DraftPost: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var text: String
    var attachments: [Attachment]
    /// Mastodon visibility for this post; ignored by Bluesky.
    var visibility: PostVisibility
    /// Mentions picked from autocomplete, rendered per network at post time.
    var mentions: [MentionSpan]

    init(id: UUID = UUID(), text: String = "", attachments: [Attachment] = [],
         visibility: PostVisibility = .public, mentions: [MentionSpan] = []) {
        self.id = id
        self.text = text
        self.attachments = attachments
        self.visibility = visibility
        self.mentions = mentions
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, attachments, visibility, mentions
    }

    /// Drafts saved before mentions existed have no `mentions` key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        attachments = try container.decode([Attachment].self, forKey: .attachments)
        visibility = try container.decode(PostVisibility.self, forKey: .visibility)
        mentions = try container.decodeIfPresent([MentionSpan].self, forKey: .mentions) ?? []
    }

    /// True when there is nothing to post: no text (after trimming) and no images.
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }

    /// This post as `target` receives it: each mention replaced with that
    /// network's form. Spans are applied last to first so earlier offsets hold;
    /// a span outside the text is left as typed.
    func rendered(for target: PostTarget) -> DraftPost {
        var copy = self
        copy.mentions = []
        guard !mentions.isEmpty else { return copy }
        let output = NSMutableString(string: text)
        for span in mentions.sorted(by: { $0.location > $1.location })
            where span.location >= 0 && NSMaxRange(span.range) <= output.length {
            output.replaceCharacters(in: span.range, with: span.person.rendered(for: target))
        }
        copy.text = output as String
        return copy
    }
}
```

- [ ] **Step 4: `xcodegen generate`, run `MentionRenderingTests` and `DraftPostTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(core): add mentions to drafts with per-network rendering`

---

### Task 2: Mention query detection (Core)

**Files:**
- Modify: `Sources/Core/Mention.swift`
- Test: `Tests/CoreTests/MentionQueryTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import CrossPost

final class MentionQueryTests: XCTestCase {
    private func detect(_ text: String, caret: Int? = nil) -> MentionQuery? {
        MentionQuery.detect(in: text, caret: caret ?? (text as NSString).length)
    }

    func testDetectsAtStartAndAfterWhitespace() {
        XCTAssertEqual(detect("@pu"), MentionQuery(range: NSRange(location: 0, length: 3), text: "pu"))
        XCTAssertEqual(detect("hi\n@pup")?.text, "pup")
        XCTAssertEqual(detect("hi @pup")?.range, NSRange(location: 3, length: 4))
    }

    func testNeedsTwoCharacters() {
        XCTAssertNil(detect("@p"))
        XCTAssertNil(detect("@"))
    }

    func testIgnoresEmailsAndWordsWithoutLeadingAt() {
        XCTAssertNil(detect("bob@example.com"))
        XCTAssertNil(detect("hello"))
    }

    func testFullAddressKeepsSecondAt() {
        XCTAssertEqual(detect("@pup@hachyderm")?.text, "pup@hachyderm")
    }

    func testCaretMustEndTheToken() {
        XCTAssertNil(detect("@puppet", caret: 4))
        XCTAssertEqual(detect("@pup more", caret: 4)?.text, "pup")
        XCTAssertNil(detect("@pup ", caret: 5))
    }

    func testEmojiBeforeQueryUsesUTF16Range() {
        let text = "👍 @al"
        XCTAssertEqual(detect(text)?.range, NSRange(location: 3, length: 3))
    }
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implement** (append to `Mention.swift`):

```swift
/// The `@` token being typed at the caret: `@` at the start of the text or after
/// whitespace, then at least two non-whitespace characters, ending at the caret.
struct MentionQuery: Equatable, Sendable {
    /// The `@` through the caret, in UTF-16 units.
    let range: NSRange
    /// What follows the `@`.
    let text: String

    static func detect(in text: String, caret: Int) -> MentionQuery? {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length else { return nil }
        if caret < ns.length, !isWhitespace(ns.character(at: caret)) {
            return nil
        }
        var start = caret
        while start > 0, !isWhitespace(ns.character(at: start - 1)) {
            start -= 1
        }
        let token = ns.substring(with: NSRange(location: start, length: caret - start))
        guard token.hasPrefix("@"), token.count >= 3 else { return nil }
        return MentionQuery(range: NSRange(location: start, length: caret - start),
                            text: String(token.dropFirst()))
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
```

- [ ] **Step 4: Run `MentionQueryTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(core): detect @-mention queries at the caret`

---

### Task 3: Validate and publish rendered text per target (Core)

**Files:**
- Modify: `Sources/Core/PostValidator.swift` (`validate`)
- Modify: `Sources/Core/CrossPostCoordinator.swift` (private `publish`)
- Test: `Tests/CoreTests/PostValidatorTests.swift`, `Tests/CoreTests/CrossPostCoordinatorTests.swift`

- [ ] **Step 1: Failing tests**

Add to `PostValidatorTests`:

```swift
    func testMentionCountsAgainstEachNetworksRenderedText() {
        let person = MentionPerson(mastodonAcct: "a@b.c",
                                   blueskyHandle: String(repeating: "x", count: 290) + ".bsky.social",
                                   displayName: "X")
        let post = DraftPost(text: "@a", mentions: [MentionSpan(location: 0, length: 2, person: person)])
        let issues = PostValidator.validate(thread: [post], targets: [.mastodon, .bluesky], limits: limits)
        XCTAssertEqual(issues, [.tooLong(postIndex: 0, target: .bluesky, count: 303, limit: 300)])
    }
```

Add to `CrossPostCoordinatorTests` (uses the file's private `StubPoster`):

```swift
    func testEachPosterReceivesItsOwnRenderedText() async {
        let person = MentionPerson(mastodonAcct: "pup@hachyderm.io",
                                   blueskyHandle: "pup.bsky.social", displayName: "Pup")
        let post = DraftPost(text: "hi @pup", mentions: [MentionSpan(location: 3, length: 4, person: person)])
        let mastodon = StubPoster(target: .mastodon, behavior: .ok([PostedItem(url: "m")]))
        let bluesky = StubPoster(target: .bluesky, behavior: .ok([PostedItem(url: "b")]))
        _ = await CrossPostCoordinator().publish(thread: [post], to: [.mastodon, .bluesky],
                                                 using: [mastodon, bluesky], limits: TargetLimits())
        XCTAssertEqual(mastodon.postedThread.map(\.text), ["hi @pup@hachyderm.io"])
        XCTAssertEqual(bluesky.postedThread.map(\.text), ["hi @pup.bsky.social"])
    }
```

- [ ] **Step 2: Run both classes, expect the two new tests to FAIL.**

- [ ] **Step 3: Implement**

In `PostValidator.validate`, render inside the target loop and use the rendered
text for both counts:

```swift
            for target in targets {
                let text = post.rendered(for: target).text
                let count = countedGraphemes(text, for: target)
                let byteCount = text.utf8.count
                ...
```

(remove the outer `let byteCount = post.text.utf8.count`).

In `CrossPostCoordinator.publish(thread:to:using:landed:)`:

```swift
        let suffix = Array(thread.dropFirst(landed.count)).map { $0.rendered(for: target) }
```

- [ ] **Step 4: Run `PostValidatorTests` and `CrossPostCoordinatorTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(core): validate and post each network's rendered mentions`

---

### Task 4: Candidate merging (Core)

**Files:**
- Create: `Sources/Core/MentionMerger.swift`
- Test: `Tests/CoreTests/MentionMergerTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import CrossPost

final class MentionMergerTests: XCTestCase {
    private func mastodon(_ acct: String, name: String = "M", profile: String = "") -> MentionCandidate {
        MentionCandidate(target: .mastodon, handle: acct, displayName: name, avatarURL: nil, profileText: profile)
    }

    private func bluesky(_ handle: String, name: String = "B") -> MentionCandidate {
        MentionCandidate(target: .bluesky, handle: handle, displayName: name, avatarURL: nil, profileText: "")
    }

    func testMergesOnProfileLinkOrHandle() {
        let link = MentionMerger.merge(
            mastodon: [mastodon("pup@hachyderm.io", profile: #"<a href="https://bsky.app/profile/Pup.bsky.social">"#)],
            bluesky: [bluesky("pup.bsky.social")], pairs: [])
        XCTAssertEqual(link.map(\.blueskyHandle), ["pup.bsky.social"])
        let handle = MentionMerger.merge(
            mastodon: [mastodon("pup@hachyderm.io", profile: "also @pup.bsky.social.")],
            bluesky: [bluesky("pup.bsky.social")], pairs: [])
        XCTAssertEqual(handle.count, 1)
    }

    func testHandleMustNotContinue() {
        let people = MentionMerger.merge(
            mastodon: [mastodon("pup@hachyderm.io", profile: "@pup.bsky.socialite")],
            bluesky: [bluesky("pup.bsky.social")], pairs: [])
        XCTAssertEqual(people.count, 2)
    }

    func testMergesBridgyFedAccounts() {
        let bridgedBluesky = MentionMerger.merge(
            mastodon: [mastodon("alice.bsky.social@bsky.brid.gy")],
            bluesky: [bluesky("alice.bsky.social")], pairs: [])
        XCTAssertEqual(bridgedBluesky.count, 1)
        let bridgedMastodon = MentionMerger.merge(
            mastodon: [mastodon("bob@mastodon.social")],
            bluesky: [bluesky("bob.mastodon.social.ap.brid.gy")], pairs: [])
        XCTAssertEqual(bridgedMastodon.count, 1)
    }

    func testMergesSavedPairCaseInsensitively() {
        let pairs = [MentionPair(mastodonAcct: "Pup@Hachyderm.io", blueskyHandle: "lk.example.com")]
        let people = MentionMerger.merge(mastodon: [mastodon("pup@hachyderm.io")],
                                         bluesky: [bluesky("LK.example.com")], pairs: pairs)
        XCTAssertEqual(people.count, 1)
    }

    func testSameNameAloneDoesNotMerge() {
        let people = MentionMerger.merge(mastodon: [mastodon("a@x.y", name: "Sam")],
                                         bluesky: [bluesky("sam.bsky.social", name: "Sam")], pairs: [])
        XCTAssertEqual(people.count, 2)
    }

    func testEachCandidateMergesOnce() {
        let profile = "@pup.bsky.social"
        let people = MentionMerger.merge(
            mastodon: [mastodon("one@x.y", profile: profile), mastodon("two@x.y", profile: profile)],
            bluesky: [bluesky("pup.bsky.social")], pairs: [])
        XCTAssertEqual(people.map(\.mastodonAcct), ["one@x.y", "two@x.y"])
        XCTAssertEqual(people.map(\.blueskyHandle), ["pup.bsky.social", nil])
    }

    func testSavedPairCompletesSingleNetworkRow() {
        let pairs = [MentionPair(mastodonAcct: "pup@hachyderm.io", blueskyHandle: "lk.example.com")]
        let people = MentionMerger.merge(mastodon: [mastodon("pup@hachyderm.io")], bluesky: [], pairs: pairs)
        XCTAssertEqual(people.first?.blueskyHandle, "lk.example.com")
        let reverse = MentionMerger.merge(mastodon: [], bluesky: [bluesky("lk.example.com")], pairs: pairs)
        XCTAssertEqual(reverse.first?.mastodonAcct, "pup@hachyderm.io")
    }

    func testRowsAlternateNetworks() {
        let people = MentionMerger.merge(mastodon: [mastodon("m1@x.y"), mastodon("m2@x.y")],
                                         bluesky: [bluesky("b1.bsky.social")], pairs: [])
        XCTAssertEqual(people.map { $0.mastodonAcct ?? $0.blueskyHandle },
                       ["m1@x.y", "b1.bsky.social", "m2@x.y"])
    }
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implement** `Sources/Core/MentionMerger.swift`:

```swift
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
            guard found.upperBound < text.endIndex else { return true }
            let next = text[found.upperBound]
            if !(next.isLetter || next.isNumber || next == "-") {
                return true
            }
            searchRange = found.upperBound ..< text.endIndex
        }
        return false
    }

    private static func interleave(_ first: [MentionPerson], _ second: [MentionPerson]) -> [MentionPerson] {
        var result: [MentionPerson] = []
        for index in 0 ..< max(first.count, second.count) {
            if index < first.count { result.append(first[index]) }
            if index < second.count { result.append(second[index]) }
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
```

- [ ] **Step 4: Run `MentionMergerTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(core): merge mention search results across networks`

---

### Task 5: Pair store (Core)

**Files:**
- Create: `Sources/Core/MentionPairStore.swift`
- Modify: `Sources/Core/Log.swift` (add `mentions` logger)
- Test: `Tests/CoreTests/MentionPairStoreTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import CrossPost

final class MentionPairStoreTests: XCTestCase {
    private var store: MentionPairStore!

    override func setUp() {
        store = MentionPairStore(url: URL.temporaryDirectory
            .appending(path: "pairs-\(UUID())/mention-pairs.json"))
    }

    func testMissingFileIsEmpty() {
        XCTAssertEqual(store.load(), [])
    }

    func testSaveRoundTripsAndReplacesEitherAccount() throws {
        try store.save(MentionPair(mastodonAcct: "a@x.y", blueskyHandle: "a.bsky.social"))
        try store.save(MentionPair(mastodonAcct: "b@x.y", blueskyHandle: "b.bsky.social"))
        try store.save(MentionPair(mastodonAcct: "A@x.y", blueskyHandle: "new.bsky.social"))
        XCTAssertEqual(store.load(), [
            MentionPair(mastodonAcct: "b@x.y", blueskyHandle: "b.bsky.social"),
            MentionPair(mastodonAcct: "A@x.y", blueskyHandle: "new.bsky.social"),
        ])
    }

    func testMalformedFileReadsAsEmpty() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), [])
    }
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implement**

`Log.swift`: `static let mentions = Logger(subsystem: subsystem, category: "mentions")`

`Sources/Core/MentionPairStore.swift`:

```swift
import Foundation

/// Account pairings made by hand, kept as plain JSON so a person or an agent can
/// edit them: `[{"mastodonAcct": "...", "blueskyHandle": "..."}]`.
struct MentionPairStore: Sendable {
    let url: URL

    /// Saved pairs; a missing file is empty, and an unreadable one is logged
    /// and treated as empty rather than blocking mention search.
    func load() -> [MentionPair] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([MentionPair].self, from: Data(contentsOf: url))
        } catch {
            Log.mentions.error("Ignoring unreadable mention pairs at \(url.path, privacy: .public): \(error)")
            return []
        }
    }

    /// Saves `pair`, replacing any existing pairing for either of its accounts.
    func save(_ pair: MentionPair) throws {
        var pairs = load().filter {
            !$0.matches(mastodonAcct: pair.mastodonAcct) && !$0.matches(blueskyHandle: pair.blueskyHandle)
        }
        pairs.append(pair)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pairs).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run `MentionPairStoreTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(core): store hand-made mention pairs as JSON`

---

### Task 6: Mention search on each network (Core)

**Files:**
- Modify: `Sources/Core/Feed/FeedService.swift` (protocol)
- Modify: `Sources/Core/Feed/MastodonFeedService.swift`, `MastodonFeedService+Mapping.swift`
- Modify: `Sources/Core/Feed/BlueskyFeedService.swift`, `BlueskyFeedService+Mapping.swift`
- Modify: `Tests/AppTests/FakeFeedService.swift`
- Test: `Tests/CoreTests/MastodonMappingTests.swift`

- [ ] **Step 1: Failing test** — in `MastodonMappingTests`, decode an `Account` the
  way existing tests in that file do, with a `note` and one field whose value
  contains `bsky.app/profile/pup.bsky.social`, then:

```swift
        let candidate = MastodonFeedService.mentionCandidate(from: account)
        XCTAssertEqual(candidate.target, .mastodon)
        XCTAssertEqual(candidate.handle, account.acct)
        XCTAssertTrue(candidate.profileText.contains("bsky.app/profile/pup.bsky.social"))
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implement**

Protocol (after `search`):

```swift
    /// Accounts matching a partial @-mention, for compose autocomplete.
    func mentionCandidates(matching query: String) async throws -> [MentionCandidate]
```

Mastodon service:

```swift
    func mentionCandidates(matching query: String) async throws -> [MentionCandidate] {
        // Resolve only a full "user@instance", so a remote account the instance
        // hasn't seen can be found without a WebFinger lookup per keystroke.
        let params = SearchAccountsParams(query: query, resolve: query.contains("@"))
        return try await client.searchAccounts(params: params, limit: 8).map(Self.mentionCandidate(from:))
    }
```

Mastodon mapping:

```swift
    static func mentionCandidate(from account: Account) -> MentionCandidate {
        MentionCandidate(target: .mastodon, handle: account.acct,
                         displayName: account.displayName ?? "",
                         avatarURL: URL(string: account.avatar),
                         profileText: ([account.note] + account.fields.map(\.value)).joined(separator: "\n"))
    }
```

Bluesky service:

```swift
    func mentionCandidates(matching query: String) async throws -> [MentionCandidate] {
        try await kit.searchActorsTypeahead(matching: query, limit: 8).actors.map(Self.mentionCandidate(from:))
    }
```

Bluesky mapping:

```swift
    /// Typeahead results carry no bio, so Bluesky candidates have no profile text.
    static func mentionCandidate(from actor: AppBskyLexicon.Actor.ProfileViewBasicDefinition) -> MentionCandidate {
        MentionCandidate(target: .bluesky, handle: actor.actorHandle, displayName: actor.displayName ?? "",
                         avatarURL: actor.avatarImageURL, profileText: "")
    }
```

Fake:

```swift
    var mentionCandidatesToReturn: [MentionCandidate] = []
    var failMentionSearch = false
    private(set) var mentionQueries: [String] = []
    func mentionCandidates(matching query: String) async throws -> [MentionCandidate] {
        mentionQueries.append(query)
        if failMentionSearch {
            throw FakeError.boom
        }
        return mentionCandidatesToReturn
    }
```

- [ ] **Step 4: Build and run `MastodonMappingTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(feed): search accounts for mention autocomplete`

---

### Task 7: Directory and completion state (App)

**Files:**
- Create: `Sources/App/Compose/MentionDirectory.swift`
- Create: `Sources/App/Compose/MentionCompletion.swift`
- Test: `Tests/AppTests/MentionCompletionTests.swift`

- [ ] **Step 1: Failing tests**

```swift
@testable import CrossPost
import XCTest

@MainActor
final class MentionCompletionTests: XCTestCase {
    private func directory(_ services: [PostTarget: FakeFeedService]) -> MentionDirectory {
        MentionDirectory(pairStore: MentionPairStore(url: URL.temporaryDirectory
                             .appending(path: "pairs-\(UUID()).json"))) { target in
            guard let service = services[target] else { throw FakeFeedService.FakeError.boom }
            return service
        }
    }

    private func candidate(_ target: PostTarget, _ handle: String) -> MentionCandidate {
        MentionCandidate(target: target, handle: handle, displayName: handle, avatarURL: nil, profileText: "")
    }

    func testSearchesSelectedNetworksAndMerges() async {
        let mastodon = FakeFeedService()
        mastodon.mentionCandidatesToReturn = [candidate(.mastodon, "pup@x.y")]
        let bluesky = FakeFeedService()
        bluesky.mentionCandidatesToReturn = [candidate(.bluesky, "pup.bsky.social")]
        let results = await directory([.mastodon: mastodon, .bluesky: bluesky])
            .search("pup", on: [.mastodon, .bluesky])
        XCTAssertEqual(results.people.count, 2)
        XCTAssertEqual(results.failed, [])
        XCTAssertEqual(mastodon.mentionQueries, ["pup"])
    }

    func testOneNetworkFailingKeepsTheOther() async {
        let bluesky = FakeFeedService()
        bluesky.mentionCandidatesToReturn = [candidate(.bluesky, "pup.bsky.social")]
        let results = await directory([.bluesky: bluesky]).search("pup", on: [.mastodon, .bluesky])
        XCTAssertEqual(results.people.map(\.blueskyHandle), ["pup.bsky.social"])
        XCTAssertEqual(results.failed, [.mastodon])
    }

    func testCompletionDebouncesAndKeepsOnlyLatestQuery() async {
        var queries: [String] = []
        let completion = MentionCompletion(debounce: .milliseconds(20)) { query in
            queries.append(query)
            return MentionDirectory.Results(people: [MentionPerson(blueskyHandle: "\(query).bsky.social",
                                                                   displayName: query)], failed: [])
        }
        completion.update(text: "@pu", caret: 3)
        completion.update(text: "@pup", caret: 4)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(queries, ["pup"])
        XCTAssertEqual(completion.people.map(\.displayName), ["pup"])
        XCTAssertTrue(completion.isActive)
    }

    func testFailureWithNoResultsShowsMessage() async {
        let completion = MentionCompletion(debounce: .zero) { _ in
            MentionDirectory.Results(people: [], failed: [.mastodon, .bluesky])
        }
        completion.update(text: "@pup", caret: 4)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(completion.failureMessage, "Couldn't search Mastodon or Bluesky.")
    }

    func testLeavingTheTokenDismisses() async {
        let completion = MentionCompletion(debounce: .zero) { _ in
            MentionDirectory.Results(people: [MentionPerson(displayName: "x")], failed: [])
        }
        completion.update(text: "@pup", caret: 4)
        try? await Task.sleep(for: .milliseconds(50))
        completion.update(text: "@pup ", caret: 5)
        XCTAssertFalse(completion.isActive)
        XCTAssertEqual(completion.people, [])
    }

    func testSelectionWraps() async {
        let completion = MentionCompletion(debounce: .zero) { _ in
            MentionDirectory.Results(people: [MentionPerson(displayName: "a"), MentionPerson(displayName: "b")],
                                     failed: [])
        }
        completion.update(text: "@ab", caret: 3)
        try? await Task.sleep(for: .milliseconds(50))
        completion.moveSelection(by: -1)
        XCTAssertEqual(completion.selected?.displayName, "b")
        completion.moveSelection(by: 1)
        XCTAssertEqual(completion.selected?.displayName, "a")
    }
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implement**

`Sources/App/Compose/MentionDirectory.swift`:

```swift
import Foundation

/// Searches each network for mention candidates and merges them into people.
/// Feed services are created on first use and dropped when credentials change.
@MainActor
final class MentionDirectory {
    typealias MakeService = @MainActor (PostTarget) async throws -> FeedService

    struct Results: Equatable, Sendable {
        var people: [MentionPerson]
        var failed: [PostTarget]
    }

    let pairStore: MentionPairStore
    private let makeService: MakeService
    private var services: [PostTarget: FeedService] = [:]
    private var credentialsObserver: NSObjectProtocol?

    init(pairStore: MentionPairStore, makeService: @escaping MakeService) {
        self.pairStore = pairStore
        self.makeService = makeService
        credentialsObserver = NotificationCenter.default.addObserver(
            forName: .crossPostCredentialsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.services = [:] }
        }
    }

    deinit {
        credentialsObserver.map(NotificationCenter.default.removeObserver)
    }

    func search(_ query: String, on targets: [PostTarget]) async -> Results {
        async let mastodon = candidates(query, on: .mastodon, if: targets.contains(.mastodon))
        async let bluesky = candidates(query, on: .bluesky, if: targets.contains(.bluesky))
        let (mastodonResult, blueskyResult) = await (mastodon, bluesky)
        let people = MentionMerger.merge(mastodon: mastodonResult ?? [], bluesky: blueskyResult ?? [],
                                         pairs: pairStore.load())
        let failed = [(PostTarget.mastodon, mastodonResult), (.bluesky, blueskyResult)]
            .filter { targets.contains($0.0) && $0.1 == nil }
            .map(\.0)
        return Results(people: Array(people.prefix(8)), failed: failed)
    }

    /// Candidates from one network: empty when it isn't searched, nil on failure.
    private func candidates(_ query: String, on target: PostTarget,
                            if enabled: Bool) async -> [MentionCandidate]? {
        guard enabled else { return [] }
        do {
            return try await service(for: target).mentionCandidates(matching: query)
        } catch {
            Log.mentions.error("Mention search failed on \(target.rawValue, privacy: .public): \(error)")
            return nil
        }
    }

    // ponytail: two concurrent first searches may each build a service; the
    // second simply replaces the first in the cache.
    private func service(for target: PostTarget) async throws -> FeedService {
        if let service = services[target] {
            return service
        }
        let service = try await makeService(target)
        services[target] = service
        return service
    }
}
```

`Sources/App/Compose/MentionCompletion.swift`:

```swift
import Foundation
import Observation

/// One editor's @-mention autocomplete: tracks the query at the caret, runs a
/// debounced search, and holds the suggestions and keyboard selection.
@MainActor
@Observable
final class MentionCompletion {
    typealias Search = @MainActor (String) async -> MentionDirectory.Results

    private(set) var query: MentionQuery?
    private(set) var people: [MentionPerson] = []
    private(set) var failureMessage: String?
    private(set) var selectedIndex = 0
    /// Set by the editor: replaces the query range with the chosen mention.
    @ObservationIgnored var insert: ((MentionPerson, NSRange) -> Void)?
    @ObservationIgnored private let search: Search
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var task: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(250), search: @escaping Search) {
        self.debounce = debounce
        self.search = search
    }

    var isActive: Bool {
        query != nil && (!people.isEmpty || failureMessage != nil)
    }

    var selected: MentionPerson? {
        people.indices.contains(selectedIndex) ? people[selectedIndex] : nil
    }

    func update(text: String, caret: Int) {
        let next = MentionQuery.detect(in: text, caret: caret)
        guard let next else {
            dismiss()
            return
        }
        let queryChanged = next.text != query?.text
        query = next
        guard queryChanged else { return }
        task?.cancel()
        task = Task { [weak self, search, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let results = await search(next.text)
            guard !Task.isCancelled else { return }
            self?.show(results)
        }
    }

    func dismiss() {
        task?.cancel()
        task = nil
        query = nil
        people = []
        failureMessage = nil
        selectedIndex = 0
    }

    func moveSelection(by delta: Int) {
        guard !people.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + people.count) % people.count
    }

    /// Inserts `person` (default: the selected row) over the query and closes.
    func choose(_ person: MentionPerson? = nil) {
        guard let person = person ?? selected, let range = query?.range else { return }
        dismiss()
        insert?(person, range)
    }

    private func show(_ results: MentionDirectory.Results) {
        people = results.people
        selectedIndex = 0
        if results.people.isEmpty, !results.failed.isEmpty {
            let names = results.failed.map(\.displayName).joined(separator: " or ")
            failureMessage = "Couldn't search \(names)."
        } else {
            failureMessage = nil
        }
    }
}
```

- [ ] **Step 4: `xcodegen generate`; run `MentionCompletionTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(compose): add mention directory and completion state`

---

### Task 8: Compose model — counter, preview, signatures, pairing

**Files:**
- Modify: `Sources/App/Compose/ComposeModel.swift`, `ComposeModel+Presentation.swift`
- Modify: `Tests/AppTests/ComposeModelTests.swift` (replace `testCounterUsesStrictestSelectedNetwork`)

- [ ] **Step 1: Failing tests** (replace the old counter test; add the rest):

```swift
    func testCounterShowsNetworkWithLeastRoom() {
        let store = AccountStore()
        let previous = store.mastodonMaxChars
        defer { store.mastodonMaxChars = previous }
        let model = ComposeModel(store: store)
        store.mastodonMaxChars = 200
        XCTAssertEqual(model.counter(for: DraftPost()), PostCounter(count: 0, limit: 200, label: "Mastodon"))
        store.mastodonMaxChars = 500
        XCTAssertEqual(model.counter(for: DraftPost()).label, "Bluesky")
        store.mastodonMaxChars = 300
        XCTAssertEqual(model.counter(for: DraftPost()).label, "Both networks")

        let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")
        let post = DraftPost(text: "@pup", mentions: [MentionSpan(location: 0, length: 4, person: person)])
        XCTAssertEqual(model.counter(for: post), PostCounter(count: 4, limit: 300, label: "Mastodon"))
        model.previewTarget = .bluesky
        XCTAssertEqual(model.counter(for: post), PostCounter(count: 3, limit: 300, label: "Bluesky"))
    }

    func testDeselectingPreviewedNetworkReturnsToEdit() {
        let model = makeModel()
        model.previewTarget = .bluesky
        model.toggle(.bluesky)
        XCTAssertNil(model.previewTarget)
    }

    func testChoosingPairedAccountUpdatesMentionAndSavesPair() throws {
        let url = URL.temporaryDirectory.appending(path: "pairs-\(UUID()).json")
        let model = ComposeModel(store: AccountStore(), mentionPairStore: MentionPairStore(url: url))
        let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")
        let span = MentionSpan(location: 0, length: 4, person: person)
        model.thread[0] = DraftPost(text: "@pup", mentions: [span])
        model.pairing = MentionPairingRequest(draftID: model.thread[0].id, span: span, target: .bluesky)
        model.completePairing(with: MentionPerson(blueskyHandle: "lk.example.com", displayName: "Luke"))
        XCTAssertEqual(model.thread[0].mentions.first?.person.blueskyHandle, "lk.example.com")
        XCTAssertEqual(model.thread[0].mentions.first?.person.mastodonAcct, "pup@hachyderm.io")
        XCTAssertNil(model.pairing)
        XCTAssertEqual(MentionPairStore(url: url).load(),
                       [MentionPair(mastodonAcct: "pup@hachyderm.io", blueskyHandle: "lk.example.com")])
    }

    func testRepointingLandedMentionLocksThatNetwork() {
        let model = makeModel()
        let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")
        model.thread[0] = DraftPost(text: "@pup", mentions: [MentionSpan(location: 0, length: 4, person: person)])
        model.handleCompletion([result(.bluesky, .partial(posted: posted, failedIndex: 1, message: "x"))])
        model.thread[0].mentions[0].person.blueskyHandle = "lk.example.com"
        XCTAssertEqual(model.lockReason(.bluesky), .prefixEdited)
    }
```

Check `result(_:_:)` and `posted` helpers exist in `ComposeModelTests` and reuse them.

- [ ] **Step 2: Run `ComposeModelTests`, expect compile failures.**

- [ ] **Step 3: Implement**

`ComposeModel.swift`:

- `selectedTargets` `didSet` additionally: `if let previewTarget, !selectedTargets.contains(previewTarget) { self.previewTarget = nil }`.
- New state:

```swift
    /// The network whose final text the cards show read-only; nil = editing.
    var previewTarget: PostTarget?
    /// A mention whose missing network account the user is choosing.
    var pairing: MentionPairingRequest?
    let mentionDirectory: MentionDirectory
```

- Init gains `mentionPairStore: MentionPairStore = .application` and
  `makeFeedService: @escaping @MainActor (PostTarget, AccountStore) async throws -> FeedService = FeedServiceFactory.make`,
  and builds `mentionDirectory = MentionDirectory(pairStore: mentionPairStore) { [store] in try await makeFeedService($0, store) }`.
- `prefixIntact(_ landed:, for target:)` compares `PostSignature(thread[index].rendered(for: target))`; `lockReason` passes `target`.
- `handleCompletion` signs `PostSignature(published[$0].rendered(for: result.target))`.
- Pairing:

```swift
    /// Networks mention search can use: selected and with an account configured.
    var mentionTargets: [PostTarget] {
        PostTarget.allCases.filter { target in
            selectedTargets.contains(target) && (target == .mastodon ? store.hasMastodon : store.hasBluesky)
        }
    }

    func searchMentions(_ query: String) async -> MentionDirectory.Results {
        await mentionDirectory.search(query, on: mentionTargets)
    }

    /// Fills the requested network's account on the mention and remembers the pair.
    func completePairing(with chosen: MentionPerson) {
        guard let request = pairing else { return }
        pairing = nil
        guard let postIndex = thread.firstIndex(where: { $0.id == request.draftID }),
              let spanIndex = thread[postIndex].mentions.firstIndex(of: request.span) else { return }
        var person = request.span.person
        switch request.target {
        case .mastodon: person.mastodonAcct = chosen.mastodonAcct
        case .bluesky: person.blueskyHandle = chosen.blueskyHandle
        }
        thread[postIndex].mentions[spanIndex].person = person
        guard let acct = person.mastodonAcct, let handle = person.blueskyHandle else { return }
        do {
            try mentionDirectory.pairStore.save(MentionPair(mastodonAcct: acct, blueskyHandle: handle))
        } catch {
            errorMessage = "Couldn't save the account pairing: \(error.userMessage)"
        }
    }
```

and at file scope:

```swift
struct MentionPairingRequest: Identifiable, Equatable {
    let draftID: UUID
    let span: MentionSpan
    let target: PostTarget
    var id: String { "\(draftID)-\(span.location)-\(target.rawValue)" }
}
```

`MentionPairStore.application` in `ComposeModel+Presentation.swift` (or a small
extension near `DraftStore.application`), using the same XCTest guard:

```swift
extension MentionPairStore {
    static let application: MentionPairStore = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return MentionPairStore(url: URL.temporaryDirectory
                .appending(path: "CrossPost-tests-\(UUID())/mention-pairs.json"))
        }
        return MentionPairStore(url: URL.applicationSupportDirectory
            .appending(path: "CrossPost/mention-pairs.json"))
    }()
}
```

`ComposeModel+Presentation.swift` — replace `characterLimit` / `limitingNetwork`:

```swift
struct PostCounter: Equatable {
    let count: Int
    let limit: Int
    let label: String?
}

    /// The counter for `post`: each shown network's rendered text counted the way
    /// its server counts, reporting the network with the least room left.
    func counter(for post: DraftPost) -> PostCounter {
        let targets = previewTarget.map { [$0] } ?? PostTarget.allCases.filter { selectedTargets.contains($0) }
        let counts: [(target: PostTarget, count: Int, limit: Int)] = targets.compactMap { target in
            guard let limit = store.limits.maxGraphemes[target] else { return nil }
            return (target, PostValidator.countedGraphemes(post.rendered(for: target).text, for: target), limit)
        }
        guard let tightest = counts.min(by: { $0.limit - $0.count < $1.limit - $1.count }) else {
            return PostCounter(count: PostValidator.graphemeCount(post.text), limit: TargetLimits.blueskyMax,
                               label: nil)
        }
        let tied = counts.filter { $0.limit - $0.count == tightest.limit - tightest.count }
        return PostCounter(count: tightest.count, limit: tightest.limit,
                           label: tied.count > 1 ? "Both networks" : tightest.target.displayName)
    }
```

- [ ] **Step 4: Run `ComposeModelTests`, `ComposeSubmissionTests`, `ComposeDraftRecoveryTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(compose): per-network counter, preview state and mention pairing`

---

### Task 9: Editor mention tracking (App)

**Files:**
- Create: `Sources/App/Compose/MentionText.swift`
- Modify: `Sources/App/Compose/PlainTextEditor.swift`
- Test: `Tests/AppTests/MentionTextTests.swift`

- [ ] **Step 1: Failing tests** — drive a real `NSTextView` (no window needed)
  through the editor's coordinator:

```swift
import AppKit
@testable import CrossPost
import XCTest

@MainActor
final class MentionTextTests: XCTestCase {
    private var text = ""
    private var mentions: [MentionSpan] = []
    private let person = MentionPerson(mastodonAcct: "pup@hachyderm.io", displayName: "Pup")

    private func makeEditor() -> (NSTextView, PlainTextEditor.Coordinator) {
        let textView = NSTextView()
        let coordinator = PlainTextEditor.Coordinator(
            text: Binding(get: { self.text }, set: { self.text = $0 }),
            mentions: Binding(get: { self.mentions }, set: { self.mentions = $0 }),
            editing: nil)
        textView.delegate = coordinator
        coordinator.textView = textView
        return (textView, coordinator)
    }

    func testInsertedMentionIsTrackedThroughEditsBeforeIt() {
        let (textView, coordinator) = makeEditor()
        textView.insertText("hi @pu", replacementRange: NSRange(location: 0, length: 0))
        coordinator.insert(person, replacing: NSRange(location: 3, length: 3))
        XCTAssertEqual(text, "hi @pup ")
        XCTAssertEqual(mentions, [MentionSpan(location: 3, length: 4, person: person)])

        textView.insertText("oh ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(mentions.map(\.location), [6])
    }

    func testTypingAfterMentionIsPlainText() {
        let (textView, coordinator) = makeEditor()
        coordinator.insert(person, replacing: NSRange(location: 0, length: 0))
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.insertText("x", replacementRange: textView.selectedRange())
        XCTAssertEqual(text, "@pupx ")
        XCTAssertEqual(mentions.map(\.length), [4])
    }

    func testEditingInsideMentionDropsIt() {
        let (textView, coordinator) = makeEditor()
        coordinator.insert(person, replacing: NSRange(location: 0, length: 0))
        textView.insertText("X", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(text, "@pXup ")
        XCTAssertEqual(mentions, [])
    }

    func testBackspaceAtEndDeletesWholeMention() {
        let (textView, coordinator) = makeEditor()
        coordinator.insert(person, replacing: NSRange(location: 0, length: 0))
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.deleteBackward(nil)
        XCTAssertEqual(text, " ")
        XCTAssertEqual(mentions, [])
    }

    func testApplyingSpansRestoresMarks() {
        let (textView, _) = makeEditor()
        textView.string = "a @pup"
        MentionText.apply([MentionSpan(location: 2, length: 4, person: person)], to: textView)
        XCTAssertEqual(MentionText.spans(in: textView.textStorage!), [MentionSpan(location: 2, length: 4, person: person)])
    }
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implement**

`Sources/App/Compose/MentionText.swift`:

```swift
import AppKit

extension NSAttributedString.Key {
    static let crossPostMention = NSAttributedString.Key("net.kartar.crosspost.mention")
}

/// Boxed per mention so adjacent mentions stay separate attribute runs (an
/// `NSObject` compares by identity, so runs never coalesce).
final class MentionMark: NSObject {
    let person: MentionPerson
    init(_ person: MentionPerson) {
        self.person = person
    }
}

/// Mentions live in the text storage as `MentionMark` attribute runs, so AppKit
/// moves them with every edit and the spans are read back rather than tracked.
@MainActor
enum MentionText {
    static func plainAttributes(for textView: NSTextView) -> [NSAttributedString.Key: Any] {
        [.font: textView.font ?? .systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]
    }

    static func markAttributes(_ person: MentionPerson) -> [NSAttributedString.Key: Any] {
        [.crossPostMention: MentionMark(person), .foregroundColor: NSColor.controlAccentColor]
    }

    static func spans(in storage: NSAttributedString) -> [MentionSpan] {
        var spans: [MentionSpan] = []
        storage.enumerateAttribute(.crossPostMention, in: NSRange(location: 0, length: storage.length)) {
            value, range, _ in
            guard let mark = value as? MentionMark else { return }
            spans.append(MentionSpan(location: range.location, length: range.length, person: mark.person))
        }
        return spans
    }

    /// Replaces all marks in `textView` with `spans` (skipping any outside the text).
    static func apply(_ spans: [MentionSpan], to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.crossPostMention, range: whole)
        storage.addAttributes(plainAttributes(for: textView), range: whole)
        for span in spans where NSMaxRange(span.range) <= storage.length {
            storage.addAttributes(markAttributes(span.person), range: span.range)
        }
        storage.endEditing()
    }

    /// The mention run ending exactly at `location`, if any.
    static func mention(endingAt location: Int, in storage: NSAttributedString) -> NSRange? {
        guard location > 0, location <= storage.length else { return nil }
        var range = NSRange()
        guard storage.attribute(.crossPostMention, at: location - 1, effectiveRange: &range) is MentionMark,
              NSMaxRange(range) == location else { return nil }
        return range
    }

    /// Mention runs an edit of `range` would break: any it overlaps, or an
    /// insertion strictly inside one. Edits at a run's edges leave it intact.
    static func brokenMentions(by range: NSRange, in storage: NSAttributedString) -> [NSRange] {
        var broken: [NSRange] = []
        storage.enumerateAttribute(.crossPostMention, in: NSRange(location: 0, length: storage.length)) {
            value, run, _ in
            guard value is MentionMark else { return }
            let overlaps = NSIntersectionRange(run, range).length > 0
            let insideInsertion = range.length == 0 && range.location > run.location
                && range.location < NSMaxRange(run)
            if overlaps || insideInsertion {
                broken.append(run)
            }
        }
        return broken
    }
}
```

`PlainTextEditor.swift` changes (keep the existing `text`-only call sites working):

```swift
/// What the compose editor needs for @-mentions.
struct MentionEditing {
    let completion: MentionCompletion
    let requestPairing: (MentionSpan, PostTarget) -> Void
}

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var mentions: Binding<[MentionSpan]>?
    var editing: MentionEditing?

    init(text: Binding<String>, mentions: Binding<[MentionSpan]>? = nil, editing: MentionEditing? = nil) {
        _text = text
        self.mentions = mentions
        self.editing = editing
    }
```

- `makeNSView`: after seeding text, `context.coordinator.textView = textView`,
  `textView.typingAttributes = MentionText.plainAttributes(for: textView)`,
  `if let mentions { MentionText.apply(mentions.wrappedValue, to: textView) }`.
- `updateNSView`: after the existing string sync, re-apply marks when the
  binding's spans differ from the storage's:
  `if let mentions, let storage = textView.textStorage, MentionText.spans(in: storage) != mentions.wrappedValue { MentionText.apply(mentions.wrappedValue, to: textView) }`.
  When the string was replaced, always re-apply.
- `makeCoordinator`: `Coordinator(text: $text, mentions: mentions, editing: editing)`;
  wire `editing?.completion.insert = { [weak coordinator] in coordinator?.insert($0, replacing: $1) }`.

`Coordinator` additions:

```swift
        weak var textView: NSTextView?
        private let mentions: Binding<[MentionSpan]>?
        private let editing: MentionEditing?

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard mentions != nil, let storage = textView.textStorage else { return true }
            if replacementString == "", range.length == 1,
               let whole = MentionText.mention(endingAt: NSMaxRange(range), in: storage) {
                deleteMention(whole, in: textView)
                return false
            }
            for run in MentionText.brokenMentions(by: range, in: storage) {
                storage.removeAttribute(.crossPostMention, range: run)
                storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: run)
            }
            textView.typingAttributes = MentionText.plainAttributes(for: textView)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            if let storage = textView.textStorage {
                mentions?.wrappedValue = MentionText.spans(in: storage)
            }
            updateCompletion(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateCompletion(textView)
        }

        private func updateCompletion(_ textView: NSTextView) {
            guard let completion = editing?.completion, let storage = textView.textStorage else { return }
            let caret = textView.selectedRange()
            guard caret.length == 0, MentionText.mention(endingAt: caret.location, in: storage) == nil else {
                completion.dismiss()
                return
            }
            completion.update(text: textView.string, caret: caret.location)
        }

        /// Replaces `range` with the mention's visible text plus a space.
        func insert(_ person: MentionPerson, replacing range: NSRange) {
            guard let textView, let storage = textView.textStorage else { return }
            let visible = person.visibleText
            let inserted = visible + " "
            guard textView.shouldChangeText(in: range, replacementString: inserted) else { return }
            storage.replaceCharacters(in: range, with: NSAttributedString(
                string: inserted, attributes: MentionText.plainAttributes(for: textView)))
            storage.addAttributes(MentionText.markAttributes(person),
                                  range: NSRange(location: range.location, length: visible.utf16.count))
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + inserted.utf16.count, length: 0))
        }

        private func deleteMention(_ range: NSRange, in textView: NSTextView) {
            guard textView.shouldChangeText(in: range, replacementString: "") else { return }
            textView.textStorage?.replaceCharacters(in: range, with: "")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
        }
```

`doCommandBy` — when `editing?.completion.isActive`, handle `moveUp(_:)` /
`moveDown(_:)` (`moveSelection(by: ∓1)`), `insertNewline(_:)` and `insertTab(_:)`
(`choose()`), `cancelOperation(_:)` (`dismiss()`), each returning `true`; otherwise
fall through to the existing Tab/Shift-Tab handling.

Context menu for pairing:

```swift
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            guard let editing, let storage = view.textStorage, charIndex < storage.length else { return menu }
            var run = NSRange()
            guard let mark = storage.attribute(.crossPostMention, at: charIndex, effectiveRange: &run)
                as? MentionMark else { return menu }
            let span = MentionSpan(location: run.location, length: run.length, person: mark.person)
            for target in PostTarget.allCases {
                let item = NSMenuItem(title: "Choose \(target.displayName) account…",
                                      action: #selector(choosePairing(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = PairingChoice(span: span, target: target)
                menu.insertItem(item, at: 0)
            }
            menu.insertItem(.separator(), at: PostTarget.allCases.count)
            return menu
        }

        @objc private func choosePairing(_ item: NSMenuItem) {
            guard let choice = item.representedObject as? PairingChoice else { return }
            editing?.requestPairing(choice.span, choice.target)
        }
```

with `private final class PairingChoice: NSObject { let span: MentionSpan; let target: PostTarget; init(...) }`
in the same file. Offering both networks lets the user re-point an existing
account as well as fill a missing one.

- [ ] **Step 4: Run `MentionTextTests` and `PlainTextEditorFocusTests`, expect PASS.**
- [ ] **Step 5: Commit** `feat(compose): track mentions as text attributes in the editor`

---

### Task 10: Views — suggestions, preview picker, pairing sheet

**Files:**
- Create: `Sources/App/Compose/MentionSuggestionList.swift`
- Create: `Sources/App/Compose/MentionPairSheet.swift`
- Modify: `Sources/App/Compose/PostCardView.swift`
- Modify: `Sources/App/Feed/ComposeColumnView.swift`

- [ ] **Step 1: Suggestion list** — `MentionSuggestionList(completion:)`: when
  `completion.isActive`, a `VStack(spacing: 0)` of rows (avatar 24pt via the
  existing avatar view used in feed rows, name in `.callout.weight(.medium)`,
  handles in `.caption` secondary, small "M"/butterfly network badges matching
  the feed's platform badge), selected row highlighted with
  `Color.accentColor.opacity(0.15)` in a rounded rectangle; `failureMessage`
  shown as a single secondary row. Clicking a row calls `completion.choose(person)`.
  Reuse the feed's existing avatar and platform-badge views — find them with
  `rg -n "struct .*Avatar|PlatformBadge" Sources/App`.

- [ ] **Step 2: PostCardView** — replace `limit`/`limitLabel` with
  `counter: PostCounter`; add `previewText: String?` (non-nil shows
  `Text(previewText).font(Theme.content).textSelection(.enabled)` in place of the
  editor at the same frame) and `mentionSearch` + `onRequestPairing` used to build
  `@State private var completion` and a `MentionEditing` for
  `PlainTextEditor(text: $post.text, mentions: $post.mentions, editing: ...)`.
  Show `MentionSuggestionList(completion:)` directly under the editor.

- [ ] **Step 3: ComposeColumnView** — pass `counter: model.counter(for: post)`,
  `previewText: model.previewTarget.map { post.rendered(for: $0).text }`,
  `mentionSearch: { await model.searchMentions($0) }`,
  `onRequestPairing: { model.pairing = MentionPairingRequest(draftID: post.id, span: $0, target: $1) }`.
  Header: between the title and "New draft…", a segmented
  `Picker("Preview", selection: $model.previewTarget)` with `Text("Edit").tag(PostTarget?.none)`
  and one `Text(target.displayName).tag(Optional(target))` per selected target,
  `.pickerStyle(.segmented).labelsHidden().fixedSize()`.
  Add `.sheet(item: $model.pairing) { MentionPairSheet(request: $0, model: model) }`.

- [ ] **Step 4: MentionPairSheet** — title "Choose \(target) account for \(name)",
  a `TextField` prefilled with the display name, results from
  `model.mentionDirectory.search(query, on: [request.target])` (debounced with
  `.task(id: query)` + `Task.sleep(for: .milliseconds(250))`), rows reusing the
  suggestion row view; picking calls `model.completePairing(with:)`; Cancel sets
  `model.pairing = nil`.

- [ ] **Step 5: Build, run the full test suite, then visually verify** — launch
  with `./build.sh --run`, type `@` plus a name in the compose box, screenshot the
  suggestion list, pick one, switch the preview picker to each network,
  screenshot; repeat in dark mode. Fix layout until it matches the feed's polish.

- [ ] **Step 6: Lint** — `swiftlint --strict`, `swiftformat --lint .`, check
  `xcodebuild` output for `warning:`; fix all.

- [ ] **Step 7: Commit** `feat(compose): mention suggestions, preview picker and pairing sheet`

---

### Task 11: Docs

- [ ] Update `CLAUDE.md` "Layout" only if a new top-level concept needs a pointer
  (mentions live in `Sources/Core/Mention*.swift` and `Sources/App/Compose/Mention*.swift`).
- [ ] Commit `docs: note mention autocomplete layout`
