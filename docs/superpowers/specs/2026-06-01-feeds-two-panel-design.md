# feeds-two-panel — Design Spec

**Date:** 2026-06-01
**Status:** Approved
**Builds on:** the existing crosspost app (cross-post Core + SwiftUI compose).

## Summary

Refocus the app from a single compose window into a **three-column main window** —
**Compose | Mastodon | Bluesky** — where each platform column shows a live feed
(Home / Mentions tabs). Cross-posting remains via a compact composer column.
Individual posts in each feed can be replied to (scoped to that one feed,
cross-post disabled), liked/favourited, reposted/boosted, and opened in the
browser. Feeds auto-poll on an interval.

## Confirmed Decisions

| Decision | Choice |
|----------|--------|
| Window layout | Three columns: Compose \| Mastodon \| Bluesky (`HSplitView`) |
| Feed source | Home timeline by default; per-panel **Home / Mentions** tabs |
| Reply UX | Reply **sheet** scoped to one feed; cross-post controls hidden |
| Refresh | **Auto-poll** on a ~60s interval + manual refresh button |
| Post actions (v1) | Reply, Like/Favourite, Repost/Boost, Open in browser |
| Compose column | Compact **single-post** cross-post box + "Expand to thread…" → existing full thread composer in a sheet |
| Feed richness | Author (display name + @handle), timestamp, text (Mastodon HTML → styled), inline image thumbnails, avatars |

## Verified SDK Support

- **TootSDK:** `getTimeline(.home) -> PagedResult<[Post]>`; `getNotifications(...)`; `favouritePost(id:)`; `boostPost(id:)`; `publishPost(PostParams)` with `inReplyToId`. `Post` exposes `account`, `content` (HTML), `mediaAttachments`, `url`, `favourited`, `reblogged`, `createdAt`.
- **ATProtoKit:** `getTimeline(...) -> feed: [FeedViewPostDefinition]`; `listNotifications(...)`; `createLikeRecord(...)`; `createRepostRecord(...)`; `createPostRecord(text:replyTo:embed:)` with `ReplyReference(root:parent:)`.

Exact signatures/labels are re-verified against the cloned SDK source at plan time.

## Architecture

```
Sources/Core/Feed/                         (logic; pure pieces unit-tested)
├── FeedPost.swift          unified post model for rendering + actions
├── FeedKind.swift          enum: .home / .mentions
├── FeedService.swift       protocol: loadFeed(_:), like/unlike, repost, reply(to:text:images:)
├── MastodonFeedService.swift   TootSDK adapter (boundary)
├── BlueskyFeedService.swift    ATProtoKit adapter (boundary)
├── HTMLRenderer.swift      Mastodon HTML → AttributedString (unit-tested)
└── FeedMerge.swift         pure: dedupe + prepend new posts on refresh (unit-tested)

Sources/App/Feed/                          (SwiftUI; boundary, screenshot-verified)
├── MainView.swift          three-column HSplitView; new window root
├── ComposeColumnView.swift compact single-post cross-post box + Expand-to-thread sheet
├── FeedPanelView.swift     one platform panel: Home/Mentions tabs, list, refresh, error/empty
├── FeedPostView.swift      one post card: avatar, name/@handle, time, text, images, action row
├── FeedPanelModel.swift    @Observable @MainActor: posts, tab, loading/error; actions; auto-poll
├── ReplySheet.swift        single-feed reply UI (no cross-post controls)
└── ReplyModel.swift        @Observable @MainActor: target post + text + images → FeedService.reply
```

The existing cross-post Core (`CrosspostCoordinator`, `PosterFactory`,
`MastodonPoster`, `BlueskyPoster`, `CredentialStore`, `PostValidator`,
`ComposeModel`, `ComposeView`) is reused unchanged. `CrosspostApp` changes its
root scene from `ComposeView` to `MainView`; `ComposeView` becomes the
"Expand to thread…" sheet.

### FeedPost (the seam)

```
struct FeedPost: Identifiable {
    id: String                 // "<platform>:<native id>" — stable, for dedupe
    target: PostTarget
    authorName: String
    authorHandle: String
    avatarURL: URL?
    date: Date
    text: AttributedString     // Mastodon: HTML-rendered; Bluesky: plain text
    images: [FeedImage]        // url + altText
    webURL: URL?
    isLiked: Bool
    isReposted: Bool
    nativeRef: NativeRef
}

enum NativeRef {
    case mastodon(statusID: String)
    // uri+cid of the post and of its thread root (for correct reply threading).
    // Plain strings, not SDK types, so FeedPost stays SDK-free; the Bluesky
    // service reconstructs StrongReference(recordURI:cidHash:) from these.
    case bluesky(uri: String, cid: String, rootURI: String, rootCID: String)
}

struct FeedImage { let url: URL; let altText: String }
```

`nativeRef` carries exactly what actions and replies need as plain values, so
neither `FeedPost` nor the UI layer imports or touches SDK types.

### FeedService

```
protocol FeedService: Sendable {
    var target: PostTarget { get }
    func loadFeed(_ kind: FeedKind) async throws -> [FeedPost]
    func like(_ post: FeedPost) async throws
    func unlike(_ post: FeedPost) async throws
    func repost(_ post: FeedPost) async throws
    func reply(to post: FeedPost, text: String, images: [Attachment]) async throws -> PostedItem
}
```

`MastodonFeedService` wraps a connected `TootClient`; `BlueskyFeedService` wraps
`ATProtoBluesky` (+ the `ATProtoKit` instance for notifications). Built by an
extended `PosterFactory` (or a sibling `FeedServiceFactory`) from `AccountStore`.

## Data Flow

1. **Launch:** `MainView` builds one `FeedPanelModel` per platform. Each loads its
   Home feed. A platform without credentials shows a "Connect in Settings" empty
   state rather than an error.
2. **Tabs:** Home ↔ Mentions calls `loadFeed(.home/.mentions)`. Mastodon mentions =
   `getNotifications` filtered to the mention type, mapped to `FeedPost`; Bluesky
   mentions = `listNotifications` filtered to `mention`/`reply` reasons (best-effort
   hydration of author/text from the notification record).
3. **Auto-poll:** each panel refreshes every ~60s (plus manual refresh). `FeedMerge`
   dedupes by `id` and prepends only genuinely-new posts, preserving order and the
   user's optimistic like/repost state.
4. **Reply:** `ReplySheet` (scoped to the post's platform, no cross-post toggles) →
   `FeedService.reply`. Mastodon sets `inReplyToId`; Bluesky builds
   `ReplyReference(root:parent:)` where `parent` is the post and `root` is its
   thread root.
5. **Like/Repost:** optimistic toggle in `FeedPanelModel`, then the SDK call; on
   failure revert and show a transient message.
6. **Open in browser:** `NSWorkspace.shared.open(webURL)`.
7. **Compose column:** a single `DraftPost` cross-posted via the unchanged
   `CrosspostCoordinator` (both targets default, length-validated, abort-on-fail).
   "Expand to thread…" opens the existing `ComposeView` thread composer in a sheet.

## Error Handling

- Per-panel banner for load / rate-limit failures, with the manual refresh to retry.
- Action failures revert the optimistic UI change and show a transient message.
- Reply errors surface inside the reply sheet.
- Missing-credential panels degrade to the "Connect in Settings" empty state.
- HTML rendering failures fall back to the stripped plain-text content.

## Testing

- **Unit (pure logic):**
  - `HTMLRenderer` — entities, tags, links, line breaks → expected styled/plain text;
    malformed HTML falls back gracefully.
  - `FeedMerge` — dedupe by id, prepend new, preserve existing order and action state,
    empty/identical/overlapping refresh sets.
  - Bluesky reply-ref construction — root vs parent selection for top-level vs nested.
- **Boundary (build + live screenshot):** the two `FeedService` adapters and all
  SwiftUI views.
- **Regression:** the existing 20 Core tests stay green.
- **Live-screenshot view testing** (standing preference): launch the app and
  screenshot and iterate on — the three-column layout; each panel's Home and Mentions
  tabs; a post card with an image and avatar; like/repost toggled states; the reply
  sheet; the compose column and its expand-to-thread sheet; and the "Connect in
  Settings" empty state. Verify each looks right, not merely that it builds.

## Out of Scope (v1)

- Pagination / infinite scroll (one page per refresh).
- Live streaming (WebSocket/firehose).
- Search, DMs, profile/thread detail views, lists/custom feeds.
- Editing or deleting feed posts.
- Quote-posts and polls rendering.
- Rich Bluesky facet rendering in the feed (links shown as text in v1).

## Noted Risks

- **Mastodon HTML rendering:** `NSAttributedString` HTML parsing is main-actor and
  not the fastest; acceptable at one-page feed sizes. `HTMLRenderer` isolates it and
  falls back to plain text.
- **Bluesky mentions hydration:** `listNotifications` items may need light shaping to
  become `FeedPost`s; kept best-effort in v1.
- **Rate limits:** ~60s polling for two platforms is well within limits; manual
  refresh is debounced by the in-flight loading flag.
