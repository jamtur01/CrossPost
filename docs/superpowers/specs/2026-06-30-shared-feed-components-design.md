# Shared feed components refactor

**Date:** 2026-06-30
**Branch:** `refactor/shared-feed-components`

## Problem

UI rendering in `Sources/App/Feed` is duplicated across views. The same post
body styling, avatar rendering, timestamp formatting, action buttons, sheet
chrome, and preview blocks are re-derived independently in each view. This
caused a real bug: the notifications feed rendered every post body in
`.secondary` and as plain (non-tappable) text, diverging from the timeline.

The goal is one source of truth per UI concept so every feed/post surface looks
and behaves consistently, and a future change lands in one place.

## Scope

In scope: the **reading surfaces** (feed, thread, notifications, quote embeds,
search, profile post/people lists) and the post-composition **sheets**.

Out of scope: DM message bubbles (`MessagesView`) keep their distinct chat
treatment (white-on-accent sent bubbles, no link styling). The compose-preview
blocks stay deliberately muted — they are unified with each other but not folded
into the rich `PostBody` treatment.

## Components

Each component is a focused unit with a clear interface. Tiny helpers live in the
existing `Components.swift`; larger views get their own files.

### 1. `PostBody` — `Sources/App/Feed/PostBody.swift` (new)

The canonical reading treatment for a post body.

```swift
struct PostBody: View {
    let text: AttributedString
    let accent: Color
    var cacheKey: String? = nil
    var font: Font = Theme.content
    var color: AnyShapeStyle = AnyShapeStyle(.primary)
    var lineLimit: Int? = nil
    let onOpenURL: (URL) -> Void
}
```

Always applies, in this order: `RichText.styled(text, accent:, cacheKey:)`,
`.font(font)`, `.foregroundStyle(color)`, `.tint(accent)`,
`.lineSpacing(Theme.bodyLineSpacing)`, `.frame(maxWidth: .infinity, alignment:
.leading)`, the in-app `openURL` environment action, and
`.textSelection(.enabled)`.

`lineLimit` handling: when `lineLimit == nil`, also apply
`.fixedSize(horizontal: false, vertical: true)` (timeline behavior). When a
limit is set, apply `.lineLimit(n)` and omit `fixedSize` (they conflict).

Adopters:
- `FeedPostView` body — `font: expanded ? .contentLarge : .content`, no limit.
- `NotificationsListView` — `lineLimit: 3`, `color:` primary for
  `.mention`/`.reply`/`.quote`, secondary otherwise (replaces the inline rich
  body added earlier in this change).
- `EmbedViews` quote embed — `font: .system(size: 13)`, `lineLimit: 6`,
  `cacheKey: quote.id`.
- Any other reading surface that renders `post.text` (thread/search/profile).

Link routing is `model.openLink(url, push: push)`, matching the existing feed
wiring.

### 2. `AvatarView` — `Sources/App/Feed/Components.swift`

```swift
struct AvatarView: View {
    let url: URL?
    var size: CGFloat
    var ring: Bool = true
}
```

`AsyncImage` (`resizable().scaledToFill()`) with a `Circle().fill(.quaternary)`
placeholder, `.frame(width: size, height: size)`, `.clipShape(Circle())`, and
when `ring` is true `.overlay(Circle().strokeBorder(Theme.avatarRing, lineWidth:
0.5))`.

Replaces the 8 hand-rolled avatars (FeedPostView, NotificationsListView,
ProfileListView, SearchView, QuoteCardView, MessagesView row + header).
`ProfileView`'s large profile-header avatar uses a bespoke double-ring overlay;
it may keep its own treatment or pass `ring: false` and add the overlay locally
— it is not forced into the shared ring.

### 3. `relativeTimestamp(_:)` — `Sources/App/Feed/Components.swift`

A `View`-returning helper: `Text(date, format: .relative(presentation:
.numeric)).font(Theme.meta).foregroundStyle(.tertiary).fixedSize()`. Replaces 3
identical sites (FeedPostView, NotificationsListView, MessagesView).

### 4. `QuotedPreviewBlock` — `Sources/App/Feed/QuotedPreviewBlock.swift` (new)

```swift
struct QuotedPreviewBlock: View {
    let post: FeedPost
    let accent: Color
}
```

The muted compose preview: accent capsule rule (`width: 3`,
`accent.opacity(0.5)`) + handle (`.caption.bold()`, `.secondary`) + body
(`.callout`, `.secondary`, `lineLimit(4)`), wrapped in the rounded
`.quaternary.opacity(0.35)` background. Replaces the byte-identical blocks in
`ReplySheet` and `QuoteSheet`. Intentionally NOT rich/tappable — it is reference
context while composing.

### 5. `ProfileRowView` — `Sources/App/Feed/ProfileRowView.swift` (new)

```swift
struct ProfileRowView: View {
    let profile: Profile          // match the existing row's model type
    let onTap: () -> Void
}
```

Avatar (`AvatarView`) + name/handle/bio `VStack` inside a `.plain` button, with
`contentShape(Rectangle())` and `hoverHighlight()`. Replaces the near-identical
`row(_:)` in ProfileListView and `personRow(_:)` in SearchView. Exact field
types confirmed against those two call sites during implementation.

### 6. Sheet chrome — `Sources/App/Feed/SheetChrome.swift` (new)

- `func sheetContainer() -> some View` modifier: `.padding(20).frame(width:
  Theme.sheetWidth)`.
- `func sheetHeader(icon: String?, label: String, accent: Color) -> some View`:
  the `HStack(spacing: 8)` header — a `Circle` dot when `icon == nil`, else
  `Image(systemName: icon)` tinted accent, then `Text(label).font(.columnTitle)`.

Adopted by ReplySheet (dot), QuoteSheet (dot), EditSheet (pencil), ReportSheet
(flag).

### 7. `PostActionBar` + unified action button — `Sources/App/Feed/PostActionBar.swift` (new)

Consolidate FeedPostView's `countAction`/`iconAction` and Notifications'
`actionButton` into one helper with an optional count:

```swift
func postActionButton(
    _ symbol: String,
    count: Int? = nil,
    active: Bool = false,
    tint: Color,
    help: String,
    action: @escaping () -> Void
) -> some View
```

Active state colors the glyph/count `tint`, otherwise `.secondary`; count uses
`.number.notation(.compactName)` with `Theme.count`. FeedPostView and
NotificationsListView both build their action rows from this helper. Whether the
whole bar becomes a `PostActionBar` view or just the button is shared is decided
during implementation based on how cleanly the two call sites converge.

## Cleanup (logic, not a component)

`NotificationsListView` hand-rolls optimistic `toggleLike`/`toggleRepost` with
local `@State` and rollback, while `FeedPostView` routes mutations through
`FeedPanelModel`. Move the notifications row to the model-based path so there is
one source of truth for like/repost optimism and rollback. This removes the
duplicated logic and the divergent failure handling. Verify the optimistic
record-URI behavior (the reason the local snapshot exists) is preserved by the
model path before deleting the local version.

## Non-goals (explicitly not extracted)

- Status badges: FeedPostView visibility glyph vs ProfileView "Follows you"
  capsule are different visual languages — no shared abstraction.
- Compact count text outside the action bar: only 2 sites, different fonts —
  a shared helper would be a passthrough.
- A generic clickable-row modifier: `hoverHighlight()` already covers simple
  rows; FeedPostView's row is timeline-aware and stays bespoke.

## Testing / verification

This is a pure refactor — rendered output should not change (except the
notifications body, which gains rich/tappable text and correct primary color for
mentions/replies, the intended fix).

- Build clean: `./build.sh`.
- Run the existing `CrossPostTests` suite; no behavior tests should break.
- Visual check (per project practice): launch the app and confirm timeline,
  thread, notifications, quote embeds, profile/search lists, and the
  reply/quote/edit/report sheets render unchanged, and that notification
  mentions/replies show primary, tappable text.

## Risks

- `PostBody`'s `lineLimit`/`fixedSize` interaction must be correct or timeline
  text will clip or notification rows will grow unbounded.
- The like/repost cleanup is the only behavior change; it carries the most risk
  and should land as its own commit with its own verification.
