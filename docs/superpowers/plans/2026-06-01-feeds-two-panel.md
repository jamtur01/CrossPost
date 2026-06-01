# feeds-two-panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn crosspost into a three-column window (Compose | Mastodon | Bluesky) where each platform column shows a live Home/Mentions feed whose posts can be replied to (scoped to that feed), liked, reposted, and opened in the browser — while keeping the existing cross-post composer.

**Architecture:** A new `Sources/Core/Feed` layer defines a platform-agnostic `FeedPost` plus a `FeedService` protocol, with `MastodonFeedService` (TootSDK) and `BlueskyFeedService` (ATProtoKit) adapters. Pure pieces (`HTMLRenderer`, `FeedMerge`, `BlueskyThreadRef`) are unit-tested; adapters and SwiftUI are boundary code verified by build + live screenshots. The existing cross-post Core is reused unchanged; `CrosspostApp`'s root scene becomes `MainView`.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+. TootSDK 21.8.0, ATProtoKit 0.32.5. XcodeGen project. Tests via `xcodebuild test`.

## Verified SDK facts (from the cloned sources — use exactly these)

**TootSDK**
- `client.getTimeline(.home) -> PagedResult<[Post]>`; posts at `.result`.
- `client.getNotifications(params: TootNotificationParams(types: [.mention])) -> PagedResult<[TootNotification]>`; `.result` is `[TootNotification]`; each has `.type`, `.account: Account`, `.post: Post?` (JSON "status").
- `Post`: `.id: String`, `.content: String?` (HTML), `.createdAt: Date`, `.account: Account`, `.mediaAttachments: [MediaAttachment]`, `.url: String?`, `.favourited: Bool?`, `.reposted: Bool?`.
- `Account`: `.displayName: String?`, `.acct: String`, `.avatar: String`.
- `MediaAttachment`: `.url: String`, `.type: OpenEnum<AttachmentType>` (`.image`), `.description: String?`.
- Actions return updated `Post`: `favouritePost(id:)`, `unfavouritePost(id:)`, `boostPost(id:)`, `unboostPost(id:)`.
- Reply: `PostParams(post:visibility:)` then set `.inReplyToId`; `client.publishPost(_:) -> Post`. Media: `UploadMediaAttachmentParams(file:thumbnail:description:focus:)`, `client.uploadMedia(_, mimeType:) -> UploadedMediaAttachment` (`.id`).

**ATProtoKit** (timeline/notifications are on the `ATProtoKit` instance; like/repost/reply/delete are on `ATProtoBluesky`)
- `kit.getTimeline() -> output` with `.feed: [AppBskyLexicon.Feed.FeedViewPostDefinition]`. Each item: `.post: PostViewDefinition`, `.reply: ReplyReferenceDefinition?`, `.reason: ReasonUnion?`.
- `PostViewDefinition`: `.uri: String`, `.cid: String`, `.author: ProfileViewBasicDefinition`, `.record: UnknownType`, `.embed: EmbedUnion?`, `.indexedAt: Date`, `.likeCount/.repostCount: Int?`, `.viewer: ViewerStateDefinition?` with `.likeURI: String?` (JSON "like") and `.repostURI: String?` (JSON "repost").
- `ProfileViewBasicDefinition`: `.actorHandle: String`, `.displayName: String?`, `.avatarImageURL: URL?`.
- Post text: `post.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)?.text`.
- Image embed: `EmbedUnion.embedImagesView(AppBskyLexicon.Embed.ImagesDefinition.View)`; `.images: [ViewImage]`; each `ViewImage`: `.fullSizeImageURL: URL`, `.thumbnailImageURL: URL`, `.altText: String`.
- `kit.listNotifications(with: [.mention, .reply]) -> output` with `.notifications: [Notification]`; each: `.author: ProfileViewDefinition`, `.reason: Reason`, `.uri/.cid: String`, `.record: UnknownType`, `.indexedAt: Date`.
- Like: `bluesky.createLikeRecord(_ strongReference) -> StrongReference`. Repost: `bluesky.createRepostRecord(_ strongReference) -> StrongReference`. Undo either: `bluesky.deleteRecord(.recordURI(atURI: <recordURI>))`.
- Reply: `bluesky.createPostRecord(text:replyTo:embed:) -> StrongReference`; `replyTo` is `AppBskyLexicon.Feed.PostRecord.ReplyReference(root:parent:)`; refs are `ComAtprotoLexicon.Repository.StrongReference(recordURI:cidHash:)` (`.recordURI`, `.recordCID`).

> **Boundary-adapter note:** ATProtoKit wraps everything in nested namespaces and uses union enums (`EmbedUnion`, `ReasonUnion`, the reply-root union). The exact case spellings may differ from the sketches below. When the compiler rejects a case name or type path, read the real declaration in the SwiftPM checkout (search under `~/Library/Developer/Xcode/DerivedData/**/SourcePackages/checkouts/ATProtoKit`) and fix ONLY the spelling, preserving behavior. Do not invent API.

---

## File Structure

```
Sources/Core/Feed/
├── FeedKind.swift
├── FeedPost.swift            FeedPost, FeedImage, NativeRef
├── HTMLRenderer.swift        Mastodon HTML → clean String   (unit-tested)
├── FeedMerge.swift           dedupe + prepend on refresh     (unit-tested)
├── BlueskyThreadRef.swift    thread-root selection           (unit-tested)
├── FeedService.swift         protocol
├── MastodonFeedService.swift TootSDK adapter (boundary)
└── BlueskyFeedService.swift  ATProtoKit adapter (boundary)
Sources/App/Feed/
├── FeedServiceFactory.swift  build services from AccountStore
├── FeedPanelModel.swift      @Observable: posts, tab, actions, auto-poll
├── ReplyModel.swift          @Observable: one-feed reply
├── MainView.swift            three-column HSplitView (window root)
├── ComposeColumnView.swift   compact cross-post box + expand-to-thread sheet
├── FeedPanelView.swift       panel: tabs, list, refresh, states
├── FeedPostView.swift        one post card + action row
└── ReplySheet.swift          reply composer (no cross-post)
Tests/CoreTests/
├── HTMLRendererTests.swift
├── FeedMergeTests.swift
└── BlueskyThreadRefTests.swift
```

Modified: `Sources/App/CrosspostApp.swift` (root → `MainView`), `Sources/App/Compose/ComposeView.swift` (accept an injected `ComposeModel`), and `Sources/App/PosterFactory.swift` (expose the `ATProtoKit` instance for Bluesky).

---

## Task 1: Feed models — FeedKind, FeedPost, FeedImage, NativeRef

**Files:**
- Create: `Sources/Core/Feed/FeedKind.swift`
- Create: `Sources/Core/Feed/FeedPost.swift`

- [ ] **Step 1: Write `FeedKind.swift`**

```swift
import Foundation

public enum FeedKind: String, CaseIterable, Sendable, Identifiable {
    case home
    case mentions

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .home: return "Home"
        case .mentions: return "Mentions"
        }
    }
}
```

- [ ] **Step 2: Write `FeedPost.swift`**

```swift
import Foundation

public struct FeedImage: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL
    public let altText: String

    public init(url: URL, altText: String) {
        self.id = url.absoluteString
        self.url = url
        self.altText = altText
    }
}

/// Platform-native handles needed to act on or reply to a post, as plain values
/// so FeedPost never imports an SDK type.
public enum NativeRef: Equatable, Sendable {
    case mastodon(statusID: String)
    case bluesky(uri: String, cid: String, rootURI: String, rootCID: String)
}

public struct FeedPost: Identifiable, Equatable, Sendable {
    public let id: String          // "<platform>:<native id>"
    public let target: PostTarget
    public let authorName: String
    public let authorHandle: String
    public let avatarURL: URL?
    public let date: Date
    public let text: AttributedString
    public let images: [FeedImage]
    public let webURL: URL?
    public var isLiked: Bool
    public var isReposted: Bool
    public var likeRecordURI: String?      // Bluesky: like record uri (for undo); nil for Mastodon
    public var repostRecordURI: String?    // Bluesky: repost record uri (for undo); nil for Mastodon
    public let nativeRef: NativeRef

    public init(id: String, target: PostTarget, authorName: String, authorHandle: String,
                avatarURL: URL?, date: Date, text: AttributedString, images: [FeedImage],
                webURL: URL?, isLiked: Bool, isReposted: Bool,
                likeRecordURI: String? = nil, repostRecordURI: String? = nil,
                nativeRef: NativeRef) {
        self.id = id; self.target = target; self.authorName = authorName
        self.authorHandle = authorHandle; self.avatarURL = avatarURL; self.date = date
        self.text = text; self.images = images; self.webURL = webURL
        self.isLiked = isLiked; self.isReposted = isReposted
        self.likeRecordURI = likeRecordURI; self.repostRecordURI = repostRecordURI
        self.nativeRef = nativeRef
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/Feed/FeedKind.swift Sources/Core/Feed/FeedPost.swift
git commit -m "Add FeedKind and FeedPost feed models"
```

---

## Task 2: HTMLRenderer (pure, full TDD)

Mastodon post content is limited HTML (`<p>`, `<br>`, `<a>`, `<span>`, entities). Render it to clean text. Pure and unit-tested; no `NSAttributedString` (keeps it deterministic).

**Files:**
- Create: `Sources/Core/Feed/HTMLRenderer.swift`
- Test: `Tests/CoreTests/HTMLRendererTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Crosspost

final class HTMLRendererTests: XCTestCase {
    func testStripsTags() {
        XCTAssertEqual(HTMLRenderer.render("<p>hello <span>world</span></p>"), "hello world")
    }

    func testParagraphsBecomeBlankLineSeparated() {
        XCTAssertEqual(HTMLRenderer.render("<p>one</p><p>two</p>"), "one\n\ntwo")
    }

    func testBrBecomesNewline() {
        XCTAssertEqual(HTMLRenderer.render("a<br>b<br/>c"), "a\nb\nc")
    }

    func testDecodesEntities() {
        XCTAssertEqual(HTMLRenderer.render("Ben &amp; Jerry &lt;3 &#39;x&#39; &quot;y&quot;"),
                       "Ben & Jerry <3 'x' \"y\"")
    }

    func testDecodesNumericEntity() {
        XCTAssertEqual(HTMLRenderer.render("caf&#233;"), "café")
    }

    func testLinkRendersAsItsText() {
        XCTAssertEqual(HTMLRenderer.render(#"see <a href="https://x.com">x.com</a>"#), "see x.com")
    }

    func testTrimsTrailingWhitespace() {
        XCTAssertEqual(HTMLRenderer.render("<p>hi</p>"), "hi")
    }

    func testEmptyAndPlain() {
        XCTAssertEqual(HTMLRenderer.render(""), "")
        XCTAssertEqual(HTMLRenderer.render("plain text"), "plain text")
    }
}
```

- [ ] **Step 2: Run tests; expect FAIL**

Run: `xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS' -only-testing:CoreTests/HTMLRendererTests`
Expected: FAIL — `HTMLRenderer` not found.

- [ ] **Step 3: Write `HTMLRenderer.swift`**

```swift
import Foundation

public enum HTMLRenderer {
    /// Convert Mastodon's limited HTML into clean plain text:
    /// `</p>` → blank line, `<br>` → newline, other tags stripped, entities decoded.
    public static func render(_ html: String) -> String {
        var s = html
        // Block/line breaks first, before stripping tags.
        s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        // Strip all remaining tags.
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ input: String) -> String {
        var s = input
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (entity, value) in named {
            s = s.replacingOccurrences(of: entity, with: value)
        }
        // Numeric decimal entities like &#233;
        while let range = s.range(of: "&#[0-9]+;", options: .regularExpression) {
            let digits = s[range].dropFirst(2).dropLast()
            if let code = UInt32(digits), let scalar = Unicode.Scalar(code) {
                s.replaceSubrange(range, with: String(scalar))
            } else {
                s.replaceSubrange(range, with: "")
            }
        }
        return s
    }
}
```

- [ ] **Step 4: Run tests; expect PASS (8 tests)**

Run: `xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS' -only-testing:CoreTests/HTMLRendererTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Feed/HTMLRenderer.swift Tests/CoreTests/HTMLRendererTests.swift
git commit -m "Add HTMLRenderer for Mastodon post content"
```

---

## Task 3: FeedMerge (pure, full TDD)

**Files:**
- Create: `Sources/Core/Feed/FeedMerge.swift`
- Test: `Tests/CoreTests/FeedMergeTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Crosspost

final class FeedMergeTests: XCTestCase {
    private func post(_ id: String, liked: Bool = false) -> FeedPost {
        FeedPost(id: id, target: .bluesky, authorName: "a", authorHandle: "@a", avatarURL: nil,
                 date: Date(timeIntervalSince1970: 0), text: AttributedString(""), images: [],
                 webURL: nil, isLiked: liked, isReposted: false, nativeRef: .mastodon(statusID: id))
    }

    func testEmptyExistingReturnsFetched() {
        let merged = FeedMerge.merge(existing: [], fetched: [post("1"), post("2")])
        XCTAssertEqual(merged.map(\.id), ["1", "2"])
    }

    func testNewPostsPrependInFetchedOrder() {
        let merged = FeedMerge.merge(existing: [post("2"), post("3")], fetched: [post("1"), post("2")])
        XCTAssertEqual(merged.map(\.id), ["1", "2", "3"]) // only "1" is new, prepended
    }

    func testFullOverlapIsUnchanged() {
        let merged = FeedMerge.merge(existing: [post("1"), post("2")], fetched: [post("1"), post("2")])
        XCTAssertEqual(merged.map(\.id), ["1", "2"])
    }

    func testExistingActionStateIsPreserved() {
        let merged = FeedMerge.merge(existing: [post("1", liked: true)], fetched: [post("1", liked: false)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isLiked) // existing optimistic state kept, not clobbered by fetched
    }
}
```

- [ ] **Step 2: Run tests; expect FAIL**

Run: `xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS' -only-testing:CoreTests/FeedMergeTests`
Expected: FAIL — `FeedMerge` not found.

- [ ] **Step 3: Write `FeedMerge.swift`**

```swift
import Foundation

public enum FeedMerge {
    /// Prepend genuinely-new fetched posts (in fetched order) ahead of existing
    /// ones. Posts already present keep their position AND their current action
    /// state (so a freshly-fetched page doesn't clobber an optimistic like).
    public static func merge(existing: [FeedPost], fetched: [FeedPost]) -> [FeedPost] {
        let existingIDs = Set(existing.map(\.id))
        let newOnes = fetched.filter { !existingIDs.contains($0.id) }
        return newOnes + existing
    }
}
```

- [ ] **Step 4: Run tests; expect PASS (4 tests)**

Run: `xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS' -only-testing:CoreTests/FeedMergeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Feed/FeedMerge.swift Tests/CoreTests/FeedMergeTests.swift
git commit -m "Add FeedMerge for refresh dedupe/prepend"
```

---

## Task 4: BlueskyThreadRef (pure, full TDD)

Captures the one piece of Bluesky reply logic worth isolating: which (uri,cid) is the thread root.

**Files:**
- Create: `Sources/Core/Feed/BlueskyThreadRef.swift`
- Test: `Tests/CoreTests/BlueskyThreadRefTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Crosspost

final class BlueskyThreadRefTests: XCTestCase {
    func testTopLevelPostIsItsOwnRoot() {
        let root = BlueskyThreadRef.root(postURI: "at://p1", postCID: "c1", replyRoot: nil)
        XCTAssertEqual(root.uri, "at://p1")
        XCTAssertEqual(root.cid, "c1")
    }

    func testNestedPostUsesThreadRoot() {
        let root = BlueskyThreadRef.root(postURI: "at://p2", postCID: "c2",
                                         replyRoot: (uri: "at://root", cid: "croot"))
        XCTAssertEqual(root.uri, "at://root")
        XCTAssertEqual(root.cid, "croot")
    }
}
```

- [ ] **Step 2: Run tests; expect FAIL**

Run: `xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS' -only-testing:CoreTests/BlueskyThreadRefTests`
Expected: FAIL — `BlueskyThreadRef` not found.

- [ ] **Step 3: Write `BlueskyThreadRef.swift`**

```swift
import Foundation

public enum BlueskyThreadRef {
    /// The (uri,cid) to store as a post's thread root so replies thread correctly:
    /// the post's own ref if it is top-level, otherwise the existing thread root.
    public static func root(postURI: String, postCID: String,
                            replyRoot: (uri: String, cid: String)?) -> (uri: String, cid: String) {
        replyRoot ?? (uri: postURI, cid: postCID)
    }
}
```

- [ ] **Step 4: Run tests; expect PASS (2 tests)**

Run: `xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS' -only-testing:CoreTests/BlueskyThreadRefTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Feed/BlueskyThreadRef.swift Tests/CoreTests/BlueskyThreadRefTests.swift
git commit -m "Add BlueskyThreadRef thread-root selection"
```

---

## Task 5: FeedService protocol

**Files:**
- Create: `Sources/Core/Feed/FeedService.swift`

- [ ] **Step 1: Write `FeedService.swift`**

```swift
import Foundation

/// A platform's feed: load posts, toggle like/repost, and reply to one post.
/// `setLiked`/`setReposted` return the updated FeedPost (new flags + record uris).
public protocol FeedService: Sendable {
    var target: PostTarget { get }
    func loadFeed(_ kind: FeedKind) async throws -> [FeedPost]
    func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost
    func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost
    func reply(to post: FeedPost, text: String, images: [Attachment]) async throws -> PostedItem
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/Feed/FeedService.swift
git commit -m "Add FeedService protocol"
```

---

## Task 6: MastodonFeedService (TootSDK adapter, boundary)

**Files:**
- Create: `Sources/Core/Feed/MastodonFeedService.swift`

Boundary code; build-verified. Uses the verified TootSDK API.

- [ ] **Step 1: Write `MastodonFeedService.swift`**

```swift
import Foundation
import TootSDK

public struct MastodonFeedService: FeedService {
    public let target: PostTarget = .mastodon
    private let client: TootClient

    public init(client: TootClient) { self.client = client }

    public func loadFeed(_ kind: FeedKind) async throws -> [FeedPost] {
        switch kind {
        case .home:
            let posts = try await client.getTimeline(.home).result
            return posts.map { Self.feedPost(from: $0) }
        case .mentions:
            let notifications = try await client.getNotifications(params: .init(types: [.mention])).result
            return notifications.compactMap { $0.post.map { Self.feedPost(from: $0) } }
        }
    }

    public func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { return post }
        let updated = liked ? try await client.favouritePost(id: id) : try await client.unfavouritePost(id: id)
        var copy = post
        copy.isLiked = updated.favourited ?? liked
        return copy
    }

    public func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .mastodon(let id) = post.nativeRef else { return post }
        let updated = reposted ? try await client.boostPost(id: id) : try await client.unboostPost(id: id)
        var copy = post
        copy.isReposted = updated.reposted ?? reposted
        return copy
    }

    public func reply(to post: FeedPost, text: String, images: [Attachment]) async throws -> PostedItem {
        guard case .mastodon(let id) = post.nativeRef else {
            throw FeedError.wrongPlatform
        }
        var mediaIds: [String] = []
        for image in images {
            let params = UploadMediaAttachmentParams(
                file: image.imageData, thumbnail: nil,
                description: image.altText.isEmpty ? nil : image.altText, focus: nil)
            mediaIds.append(try await client.uploadMedia(params, mimeType: "image/jpeg").id)
        }
        var params = PostParams(post: text, visibility: .public)
        if !mediaIds.isEmpty { params.mediaIds = mediaIds }
        params.inReplyToId = id
        let posted = try await client.publishPost(params)
        return PostedItem(url: posted.url)
    }

    static func feedPost(from post: Post) -> FeedPost {
        let images = post.mediaAttachments
            .filter { $0.type.value == .image }
            .compactMap { att -> FeedImage? in
                guard let url = URL(string: att.url) else { return nil }
                return FeedImage(url: url, altText: att.description ?? "")
            }
        return FeedPost(
            id: "mastodon:\(post.id)",
            target: .mastodon,
            authorName: post.account.displayName?.isEmpty == false ? post.account.displayName! : post.account.acct,
            authorHandle: "@\(post.account.acct)",
            avatarURL: URL(string: post.account.avatar),
            date: post.createdAt,
            text: AttributedString(HTMLRenderer.render(post.content ?? "")),
            images: images,
            webURL: post.url.flatMap(URL.init(string:)),
            isLiked: post.favourited ?? false,
            isReposted: post.reposted ?? false,
            nativeRef: .mastodon(statusID: post.id))
    }
}

public enum FeedError: Error, CustomStringConvertible {
    case wrongPlatform
    case notSupported(String)
    public var description: String {
        switch self {
        case .wrongPlatform: return "This action does not apply to this post's platform"
        case .notSupported(let what): return what
        }
    }
}
```

> If `att.type.value` isn't the right way to read the `OpenEnum<AttachmentType>` (e.g. it's `att.type` directly or `att.type.rawValue`), fix to match the real `OpenEnum` accessor — keep the "image only" filter.

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/Feed/MastodonFeedService.swift
git commit -m "Add MastodonFeedService TootSDK adapter"
```

---

## Task 7: BlueskyFeedService (ATProtoKit adapter, boundary)

**Files:**
- Create: `Sources/Core/Feed/BlueskyFeedService.swift`

Boundary code; build-verified. This is the fiddliest adapter — expect to adjust union case spellings against the compiler per the boundary-adapter note.

- [ ] **Step 1: Write `BlueskyFeedService.swift`**

```swift
import Foundation
import ATProtoKit

public struct BlueskyFeedService: FeedService {
    public let target: PostTarget = .bluesky
    private let kit: ATProtoKit
    private let bluesky: ATProtoBluesky
    private let handle: String

    public init(kit: ATProtoKit, bluesky: ATProtoBluesky, handle: String) {
        self.kit = kit
        self.bluesky = bluesky
        self.handle = handle
    }

    public func loadFeed(_ kind: FeedKind) async throws -> [FeedPost] {
        switch kind {
        case .home:
            let output = try await kit.getTimeline()
            return output.feed.compactMap { Self.feedPost(from: $0, handle: handle) }
        case .mentions:
            let output = try await kit.listNotifications(with: [.mention, .reply])
            return output.notifications.compactMap { Self.feedPost(fromNotification: $0, handle: handle) }
        }
    }

    public func setLiked(_ liked: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { return post }
        var copy = post
        if liked {
            let ref = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
            let likeRef = try await bluesky.createLikeRecord(ref)
            copy.isLiked = true
            copy.likeRecordURI = likeRef.recordURI
        } else if let likeURI = post.likeRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: likeURI))
            copy.isLiked = false
            copy.likeRecordURI = nil
        }
        return copy
    }

    public func setReposted(_ reposted: Bool, on post: FeedPost) async throws -> FeedPost {
        guard case .bluesky(let uri, let cid, _, _) = post.nativeRef else { return post }
        var copy = post
        if reposted {
            let ref = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
            let repostRef = try await bluesky.createRepostRecord(ref)
            copy.isReposted = true
            copy.repostRecordURI = repostRef.recordURI
        } else if let repostURI = post.repostRecordURI {
            try await bluesky.deleteRecord(.recordURI(atURI: repostURI))
            copy.isReposted = false
            copy.repostRecordURI = nil
        }
        return copy
    }

    public func reply(to post: FeedPost, text: String, images: [Attachment]) async throws -> PostedItem {
        guard case .bluesky(let uri, let cid, let rootURI, let rootCID) = post.nativeRef else {
            throw FeedError.wrongPlatform
        }
        let parent = ComAtprotoLexicon.Repository.StrongReference(recordURI: uri, cidHash: cid)
        let root = ComAtprotoLexicon.Repository.StrongReference(recordURI: rootURI, cidHash: rootCID)
        let replyRef = AppBskyLexicon.Feed.PostRecord.ReplyReference(root: root, parent: parent)

        var embed: ATProtoBluesky.EmbedIdentifier?
        if !images.isEmpty {
            let queries = try images.prefix(4).map { image in
                let jpeg = try ImageProcessor.jpegUnderBudget(image.imageData)
                return ATProtoTools.ImageQuery(
                    imageData: jpeg, fileName: "\(image.id.uuidString).jpg",
                    altText: image.altText.isEmpty ? nil : image.altText, aspectRatio: nil)
            }
            embed = .images(images: Array(queries))
        }
        let ref = try await bluesky.createPostRecord(text: text, replyTo: replyRef, embed: embed)
        let rkey = ref.recordURI.split(separator: "/").last.map(String.init) ?? ""
        return PostedItem(url: "https://bsky.app/profile/\(handle)/post/\(rkey)")
    }

    static func feedPost(from item: AppBskyLexicon.Feed.FeedViewPostDefinition, handle: String) -> FeedPost? {
        let p = item.post
        let text = p.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)?.text ?? ""

        // Images embed (case spelling may need adjustment).
        var images: [FeedImage] = []
        if case .embedImagesView(let view)? = p.embed {
            images = view.images.map { FeedImage(url: $0.fullSizeImageURL, altText: $0.altText) }
        }

        // Thread root: from the feed item's reply root if present, else the post itself.
        let replyRoot: (uri: String, cid: String)?
        if case .postView(let rootPost)? = item.reply?.root {
            replyRoot = (rootPost.uri, rootPost.cid)
        } else {
            replyRoot = nil
        }
        let root = BlueskyThreadRef.root(postURI: p.uri, postCID: p.cid, replyRoot: replyRoot)

        let rkey = p.uri.split(separator: "/").last.map(String.init) ?? ""
        return FeedPost(
            id: "bluesky:\(p.uri)",
            target: .bluesky,
            authorName: p.author.displayName?.isEmpty == false ? p.author.displayName! : p.author.actorHandle,
            authorHandle: "@\(p.author.actorHandle)",
            avatarURL: p.author.avatarImageURL,
            date: p.indexedAt,
            text: AttributedString(text),
            images: images,
            webURL: URL(string: "https://bsky.app/profile/\(p.author.actorHandle)/post/\(rkey)"),
            isLiked: p.viewer?.likeURI != nil,
            isReposted: p.viewer?.repostURI != nil,
            likeRecordURI: p.viewer?.likeURI,
            repostRecordURI: p.viewer?.repostURI,
            nativeRef: .bluesky(uri: p.uri, cid: p.cid, rootURI: root.uri, rootCID: root.cid))
    }

    static func feedPost(fromNotification n: AppBskyLexicon.Notification.Notification, handle: String) -> FeedPost? {
        let text = n.record.getRecord(ofType: AppBskyLexicon.Feed.PostRecord.self)?.text ?? ""
        let rkey = n.uri.split(separator: "/").last.map(String.init) ?? ""
        return FeedPost(
            id: "bluesky:\(n.uri)",
            target: .bluesky,
            authorName: n.author.displayName?.isEmpty == false ? n.author.displayName! : n.author.actorHandle,
            authorHandle: "@\(n.author.actorHandle)",
            avatarURL: n.author.avatarImageURL,
            date: n.indexedAt,
            text: AttributedString(text),
            images: [],
            webURL: URL(string: "https://bsky.app/profile/\(n.author.actorHandle)/post/\(rkey)"),
            isLiked: false,
            isReposted: false,
            nativeRef: .bluesky(uri: n.uri, cid: n.cid, rootURI: n.uri, rootCID: n.cid))
    }
}
```

> Likely adjustment points (read the real declarations and fix spellings only):
> - The embed union case `.embedImagesView(_)` and the images view's property names (`images`, `fullSizeImageURL`, `altText`).
> - `item.reply?.root` union case for a post view (`.postView(_)`); if it isn't easily destructured, set `replyRoot = nil` (reply still works, threading to the post itself).
> - `ProfileViewDefinition` (notifications author) vs `ProfileViewBasicDefinition` (feed author): both expose `actorHandle`, `displayName`, `avatarImageURL`; adjust if a name differs.
> - `kit.getTimeline()` / `kit.listNotifications(with:)` argument labels.

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **` (fix union case spellings per the notes until it builds).

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/Feed/BlueskyFeedService.swift
git commit -m "Add BlueskyFeedService ATProtoKit adapter"
```

---

## Task 8: Expose ATProtoKit instance + FeedServiceFactory

`BlueskyFeedService` needs the `ATProtoKit` instance (for timeline/notifications). Modify `PosterFactory.makeBluesky` to also return the kit, and add a factory for feed services.

**Files:**
- Modify: `Sources/App/PosterFactory.swift`
- Create: `Sources/App/Feed/FeedServiceFactory.swift`

- [ ] **Step 1: Add a kit-returning helper to `PosterFactory.swift`**

Add this method inside `enum PosterFactory` (keep the existing `makeBluesky`):

```swift
    /// Authenticate Bluesky and return both the kit (for reads) and the Bluesky client (for writes).
    @MainActor
    static func makeBlueskyClients(_ store: AccountStore) async throws -> (kit: ATProtoKit, bluesky: ATProtoBluesky) {
        let config = ATProtocolConfiguration()
        try await config.authenticate(with: store.blueskyHandle, password: store.blueskyAppPassword)
        let kit = await ATProtoKit(sessionConfiguration: config)
        let bluesky = ATProtoBluesky(atProtoKitInstance: kit)
        return (kit, bluesky)
    }
```

- [ ] **Step 2: Write `FeedServiceFactory.swift`**

```swift
import Foundation
import TootSDK
import ATProtoKit

enum FeedServiceFactory {
    @MainActor
    static func make(for target: PostTarget, store: AccountStore) async throws -> FeedService {
        switch target {
        case .mastodon:
            guard let url = URL(string: store.mastodonInstanceURL) else {
                throw PosterFactory.ConfigError.message("Invalid Mastodon instance URL")
            }
            let client = TootClient(instanceURL: url, accessToken: store.mastodonToken)
            try await client.connect()
            return MastodonFeedService(client: client)
        case .bluesky:
            let clients = try await PosterFactory.makeBlueskyClients(store)
            return BlueskyFeedService(kit: clients.kit, bluesky: clients.bluesky, handle: store.blueskyHandle)
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/App/PosterFactory.swift Sources/App/Feed/FeedServiceFactory.swift
git commit -m "Add FeedServiceFactory and expose ATProtoKit instance"
```

---

## Task 9: FeedPanelModel (app state, boundary)

**Files:**
- Create: `Sources/App/Feed/FeedPanelModel.swift`

- [ ] **Step 1: Write `FeedPanelModel.swift`**

```swift
import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class FeedPanelModel {
    let target: PostTarget
    var kind: FeedKind = .home
    var posts: [FeedPost] = []
    var isLoading = false
    var errorMessage: String?
    var needsCredentials = false

    private let store: AccountStore
    private var service: FeedService?
    private var pollTask: Task<Void, Never>?
    private let pollInterval: UInt64 = 60_000_000_000 // 60s in nanoseconds

    init(target: PostTarget, store: AccountStore) {
        self.target = target
        self.store = store
    }

    private var hasCredentials: Bool {
        target == .mastodon ? store.hasMastodon : store.hasBluesky
    }

    func start() {
        guard hasCredentials else { needsCredentials = true; return }
        Task { await load(reset: true) }
        startPolling()
    }

    func switchTo(_ newKind: FeedKind) {
        guard newKind != kind else { return }
        kind = newKind
        posts = []
        Task { await load(reset: true) }
    }

    func refresh() { Task { await load(reset: false) } }

    private func load(reset: Bool) async {
        guard hasCredentials else { needsCredentials = true; return }
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let svc = try await resolveService()
            let fetched = try await svc.loadFeed(kind)
            posts = reset ? fetched : FeedMerge.merge(existing: posts, fetched: fetched)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func resolveService() async throws -> FeedService {
        if let service { return service }
        let svc = try await FeedServiceFactory.make(for: target, store: store)
        service = svc
        return svc
    }

    func toggleLike(_ post: FeedPost) {
        mutate(post) { svc, p in try await svc.setLiked(!p.isLiked, on: p) }
    }

    func toggleRepost(_ post: FeedPost) {
        mutate(post) { svc, p in try await svc.setReposted(!p.isReposted, on: p) }
    }

    func openInBrowser(_ post: FeedPost) {
        guard let url = post.webURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Optimistically toggle, call the service, reconcile or revert on failure.
    private func mutate(_ post: FeedPost, _ action: @escaping (FeedService, FeedPost) async throws -> FeedPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let original = posts[index]
        Task {
            do {
                let svc = try await resolveService()
                let updated = try await action(svc, original)
                if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = updated }
            } catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = original }
                errorMessage = String(describing: error)
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pollInterval ?? 60_000_000_000)
                if Task.isCancelled { break }
                await self?.load(reset: false)
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/App/Feed/FeedPanelModel.swift
git commit -m "Add FeedPanelModel with auto-poll and optimistic actions"
```

---

## Task 10: ReplyModel (app state, boundary)

**Files:**
- Create: `Sources/App/Feed/ReplyModel.swift`

- [ ] **Step 1: Write `ReplyModel.swift`**

```swift
import Foundation
import SwiftUI

@MainActor
@Observable
final class ReplyModel {
    let post: FeedPost
    var text: String = ""
    var attachments: [Attachment] = []
    var isSending = false
    var errorMessage: String?
    var postedURL: String?

    private let store: AccountStore

    init(post: FeedPost, store: AccountStore) {
        self.post = post
        self.store = store
    }

    var canSend: Bool { !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let service = try await FeedServiceFactory.make(for: post.target, store: store)
            let item = try await service.reply(to: post, text: text, images: attachments)
            postedURL = item.url ?? "Sent."
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sources/App/Feed/ReplyModel.swift
git commit -m "Add ReplyModel for single-feed replies"
```

---

## Task 11: Refactor ComposeView to take an injected model

`ComposeColumnView` (next task) and the "Expand to thread…" sheet must share one `ComposeModel`. Change `ComposeView` to accept it instead of building its own.

**Files:**
- Modify: `Sources/App/Compose/ComposeView.swift`

- [ ] **Step 1: Replace the `ComposeView` declaration head**

Change the top of `ComposeView` from the environment/optional-model form to an injected `@Bindable` model. Replace:

```swift
struct ComposeView: View {
    @EnvironmentObject var store: AccountStore
    @State private var model: ComposeModel?

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .onAppear { if model == nil { model = ComposeModel(store: store) } }
    }

    @ViewBuilder
    private func content(_ model: ComposeModel) -> some View {
        @Bindable var model = model
```

with:

```swift
struct ComposeView: View {
    @Bindable var model: ComposeModel

    var body: some View {
        content(model)
    }

    @ViewBuilder
    private func content(_ model: ComposeModel) -> some View {
        @Bindable var model = model
```

Leave the rest of the file (the `content` body, `actionBar`, `blockedBanner`, `describe`) unchanged.

- [ ] **Step 2: Build (expect an error at the old call site)**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: FAIL — `CrosspostApp.swift` still constructs `ComposeView()` with no model. That call site is replaced in Task 14; for now, temporarily update `CrosspostApp.swift`'s `WindowGroup` body to `ComposeView(model: ComposeModel(store: store))` so the build is green. (Task 14 replaces this with `MainView`.)

- [ ] **Step 3: Build green**

Run: `xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run full tests (regression)**

Run: `xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Sources/App/Compose/ComposeView.swift Sources/App/CrosspostApp.swift
git commit -m "Make ComposeView take an injected ComposeModel"
```

---

## Task 12: FeedPostView + ReplySheet (views; build-verified, screenshotted in Task 14)

**Files:**
- Create: `Sources/App/Feed/FeedPostView.swift`
- Create: `Sources/App/Feed/ReplySheet.swift`

- [ ] **Step 1: Write `FeedPostView.swift`**

```swift
import SwiftUI

struct FeedPostView: View {
    let post: FeedPost
    let onReply: () -> Void
    let onLike: () -> Void
    let onRepost: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                AsyncImage(url: post.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(post.authorName).font(.subheadline.bold()).lineLimit(1)
                    Text(post.authorHandle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(post.date, format: .relative(presentation: .numeric))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text(post.text).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !post.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.images) { image in
                            AsyncImage(url: image.url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 120, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel(image.altText)
                        }
                    }
                }
            }

            HStack(spacing: 18) {
                Button(action: onReply) { Image(systemName: "arrowshape.turn.up.left") }
                    .help("Reply")
                Button(action: onLike) {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(post.isLiked ? .red : .secondary)
                }.help("Like")
                Button(action: onRepost) {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundStyle(post.isReposted ? .green : .secondary)
                }.help("Repost")
                Spacer()
                Button(action: onOpen) { Image(systemName: "safari") }.help("Open in browser")
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
```

- [ ] **Step 2: Write `ReplySheet.swift`**

```swift
import SwiftUI

struct ReplySheet: View {
    @State var model: ReplyModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reply on \(model.post.target.displayName)").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.post.authorHandle).font(.caption.bold()).foregroundStyle(.secondary)
                Text(model.post.text).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))

            TextEditor(text: $model.text)
                .font(.body).frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button(model.isSending ? "Sending…" : "Reply") {
                    Task { await model.send(); if model.errorMessage == nil { onClose() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSend)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Feed/FeedPostView.swift Sources/App/Feed/ReplySheet.swift
git commit -m "Add FeedPostView and ReplySheet"
```

---

## Task 13: FeedPanelView + ComposeColumnView (views; build-verified)

**Files:**
- Create: `Sources/App/Feed/FeedPanelView.swift`
- Create: `Sources/App/Feed/ComposeColumnView.swift`

- [ ] **Step 1: Write `FeedPanelView.swift`**

```swift
import SwiftUI

struct FeedPanelView: View {
    @State var model: FeedPanelModel
    @EnvironmentObject var store: AccountStore
    @State private var replyTarget: FeedPost?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.target.displayName).font(.headline)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Picker("Feed", selection: Binding(get: { model.kind }, set: { model.switchTo($0) })) {
                ForEach(FeedKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $replyTarget) { post in
            ReplySheet(model: ReplyModel(post: post, store: store)) { replyTarget = nil }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if model.needsCredentials {
            emptyState("Connect \(model.target.displayName) in Settings (⌘,)", systemImage: "person.crop.circle.badge.plus")
        } else if let error = model.errorMessage, model.posts.isEmpty {
            emptyState(error, systemImage: "exclamationmark.triangle")
        } else if model.posts.isEmpty && model.isLoading {
            Spacer(); ProgressView(); Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.posts) { post in
                        FeedPostView(
                            post: post,
                            onReply: { replyTarget = post },
                            onLike: { model.toggleLike(post) },
                            onRepost: { model.toggleRepost(post) },
                            onOpen: { model.openInBrowser(post) })
                    }
                }
                .padding(10)
            }
        }
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}
```

> `.sheet(item:)` requires `FeedPost: Identifiable` (it is). If the compiler wants `Hashable` for the segmented `.tag`, `FeedKind` is `Hashable` via `String` rawValue — fine.

- [ ] **Step 2: Write `ComposeColumnView.swift`**

```swift
import SwiftUI

struct ComposeColumnView: View {
    @EnvironmentObject var store: AccountStore
    @State private var model: ComposeModel?
    @State private var showThread = false

    var body: some View {
        Group {
            if let model { content(model) } else { Color.clear.onAppear { model = ComposeModel(store: store) } }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func content(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Text("New Post").font(.headline)

            TextEditor(text: Binding(
                get: { model.thread.first?.text ?? "" },
                set: { if !model.thread.isEmpty { model.thread[0].text = $0 } }))
                .font(.body).frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                ForEach(PostTarget.allCases) { target in
                    Toggle(target.displayName, isOn: Binding(
                        get: { model.selectedTargets.contains(target) },
                        set: { _ in model.toggle(target) }))
                    .toggleStyle(.button).controlSize(.small)
                }
            }

            HStack {
                Button("Expand to thread…") { showThread = true }
                    .buttonStyle(.borderless).font(.caption)
                Spacer()
                Button(model.isPosting ? "Posting…" : "Post") { Task { await model.submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canPost)
            }

            if let issues = model.blockedIssues, !issues.isEmpty {
                Text("Too long or empty — fix before posting.").font(.caption).foregroundStyle(.red)
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            Spacer()
        }
        .padding(12)
        .sheet(isPresented: $showThread) {
            VStack(spacing: 0) {
                HStack { Text("Thread").font(.headline); Spacer(); Button("Done") { showThread = false } }
                    .padding(12)
                Divider()
                ComposeView(model: model)
            }
            .frame(minWidth: 600, minHeight: 520)
        }
        .sheet(isPresented: Binding(get: { model.results != nil }, set: { if !$0 { model.results = nil } })) {
            if let results = model.results {
                ResultsSheet(results: results) { model.results = nil }
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Feed/FeedPanelView.swift Sources/App/Feed/ComposeColumnView.swift
git commit -m "Add FeedPanelView and ComposeColumnView"
```

---

## Task 14: MainView + app wiring + live visual verification

**Files:**
- Create: `Sources/App/Feed/MainView.swift`
- Modify: `Sources/App/CrosspostApp.swift`

- [ ] **Step 1: Write `MainView.swift`**

```swift
import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: AccountStore

    var body: some View {
        HSplitView {
            ComposeColumnView()
                .environmentObject(store)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            FeedPanelView(model: FeedPanelModel(target: .mastodon, store: store))
                .environmentObject(store)
                .frame(minWidth: 320)

            FeedPanelView(model: FeedPanelModel(target: .bluesky, store: store))
                .environmentObject(store)
                .frame(minWidth: 320)
        }
        .frame(minWidth: 980, minHeight: 560)
    }
}
```

- [ ] **Step 2: Update `CrosspostApp.swift` root scene**

Replace the `WindowGroup` body so the app launches into `MainView` (keep the `Settings` scene and `@StateObject store`):

```swift
import SwiftUI

@main
struct CrosspostApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        WindowGroup("Crosspost") {
            MainView().environmentObject(store)
        }
        .defaultSize(width: 1180, height: 720)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
```

- [ ] **Step 3: Build + full test regression**

Run: `xcodegen generate && xcodebuild build -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** BUILD SUCCEEDED **`
Run: `xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'`
Expected: `** TEST SUCCEEDED **` (all unit tests green: existing 20 + HTMLRenderer 8 + FeedMerge 4 + BlueskyThreadRef 2 = 34).

- [ ] **Step 4: Live visual verification (the controller does this, per the standing preference)**

Build the `.app`, launch it, and screenshot — do NOT rely on the build alone:
1. Find the product: `xcodebuild -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS' -showBuildSettings | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}'` then `open "<dir>/Crosspost.app"`.
2. Capture the window via its bounds (`osascript ... get {position, size} of front window`, then `screencapture -x -R x,y,w,h out.png`), all activate+capture in a single shell invocation so the window stays frontmost.
3. Verify and iterate until each looks right:
   - Three columns: Compose | Mastodon | Bluesky, with sensible widths and dividers.
   - With no credentials: both feed panels show the "Connect in Settings" empty state.
   - After configuring accounts (ask the user, or screenshot the empty state if credentials aren't available): feeds populate; a post card shows avatar, name/@handle, relative time, text, image thumbnails, and the Reply/Like/Repost/Open action row.
   - Home/Mentions segmented tabs switch.
   - Reply sheet opens scoped to one platform (no cross-post toggles), showing the quoted post.
   - Compose column posts and "Expand to thread…" opens the full composer sheet.
4. Fix any layout/opacity/clipping issues found (as with the prior milestone's transparent-window bug) and rebuild before committing.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/Feed/MainView.swift Sources/App/CrosspostApp.swift
git commit -m "Add MainView three-column layout and launch into it"
```

---

## Task 15: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a "Feeds" section after the Behavior section**

Append to `README.md`:

```markdown
## Feeds

The app opens into three columns — Compose | Mastodon | Bluesky. Each feed column
has Home and Mentions tabs and auto-refreshes (~60s) plus a manual refresh button.
For any post you can:

- **Reply** — opens a composer scoped to that one platform (cross-post disabled).
- **Like / Repost** — toggles favourite/boost (Mastodon) or like/repost (Bluesky).
- **Open in browser** — opens the original post.

The Compose column cross-posts a single post to both platforms (length-validated,
abort-on-fail); "Expand to thread…" opens the full thread composer. A platform
without saved credentials shows a "Connect in Settings" prompt instead of a feed.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document feeds in README"
```

---

## Self-Review Notes (addressed)

- **Spec coverage:** three-column layout (T14), Compose column + expand-to-thread (T11/T13), Home/Mentions tabs (T9/T13), auto-poll (T9), reply scoped to one feed (T10/T12), like/repost with undo (T6/T7/T9), open-in-browser (T9/T12), feed richness incl. HTML + images + avatars (T2/T6/T7/T12), missing-credential empty state (T9/T13), unified SDK-free `FeedPost` (T1), pure-logic tests (T2/T3/T4), live screenshot verification (T14). All spec sections map to tasks.
- **Type consistency:** `FeedService.loadFeed/setLiked/setReposted/reply`, `FeedPost`/`NativeRef`/`FeedImage`, `FeedMerge.merge`, `BlueskyThreadRef.root`, `HTMLRenderer.render`, `FeedServiceFactory.make`, `FeedPanelModel`/`ReplyModel`, `ComposeView(model:)` are used identically across tasks.
- **Boundary vs logic:** pure pieces (HTMLRenderer, FeedMerge, BlueskyThreadRef) are unit-tested; SDK adapters and SwiftUI are build-and-screenshot verified. Existing 20 Core tests stay green (T11/T14 run the full suite).
- **Known boundary risk:** ATProtoKit union case spellings (embed images, reply-root, notification author type) may need compiler-driven fixes — flagged inline in Task 7 with how to resolve.
