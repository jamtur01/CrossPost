# Shared Feed Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract one source of truth per UI concept (post body, avatar, timestamp, action button, sheet chrome, quoted preview, profile row) so every feed/post surface renders consistently.

**Architecture:** New focused `View`s and small helpers in `Sources/App/Feed`; tiny helpers go in the existing `Components.swift`, larger views get their own files. Each reading surface and sheet then composes these instead of re-deriving modifiers. One behavior change: route the notifications row's like/repost through `FeedPanelModel` like the timeline does.

**Tech Stack:** Swift, SwiftUI, XcodeGen (`project.yml`), `xcodebuild`. Verification: `./build.sh` + `xcodebuild test`.

**Verification model:** These are extraction refactors with no intended visual change (the one exception is the notifications body, fixed in Task 1). For each task: build clean, run the `CrossPostTests` suite, confirm green. New `.swift` files require `xcodegen generate` before they compile (the project file is generated, not checked in).

---

## File Structure

- Create: `Sources/App/Feed/PostBody.swift` — canonical post-body text view.
- Create: `Sources/App/Feed/QuotedPreviewBlock.swift` — muted compose preview block.
- Create: `Sources/App/Feed/ProfileRowView.swift` — avatar + identity list row.
- Create: `Sources/App/Feed/SheetChrome.swift` — sheet container modifier + header.
- Create: `Sources/App/Feed/PostActionBar.swift` — unified action button helper.
- Modify: `Sources/App/Feed/Components.swift` — add `AvatarView`, `relativeTimestamp`.
- Modify (adopters): `FeedPostView.swift`, `NotificationsListView.swift`,
  `EmbedViews.swift` (contains `QuoteCardView`), `ProfileListView.swift`,
  `SearchView.swift`, `MessagesView.swift`, `ProfileView.swift`,
  `ReplySheet.swift`, `QuoteSheet.swift`, `EditSheet.swift`, `ReportSheet.swift`.

---

## Task 1: Land the notifications body fix as a discrete commit

The working tree already contains the reported bug fix (conditional primary/secondary color + rich, tappable body) in `NotificationsListView.swift`. Commit it on its own before refactoring, so the user-visible fix is bisectable. Task 7 later replaces the inline body with `PostBody`.

**Files:**
- Modify: `Sources/App/Feed/NotificationsListView.swift` (already edited in working tree)

- [ ] **Step 1: Confirm the working-tree diff is only the notifications body fix**

Run: `git diff --stat`
Expected: only `Sources/App/Feed/NotificationsListView.swift` listed.

- [ ] **Step 2: Build**

Run: `./build.sh`
Expected: `==> Built: .../CrossPost.app`, no compile errors. (Stale SourceKit "Cannot find type" diagnostics are index noise; the build is the source of truth.)

- [ ] **Step 3: Test**

Run: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Feed/NotificationsListView.swift
git commit -m "Fix notification body color and make mentions tappable"
```

---

## Task 2: `AvatarView` + `relativeTimestamp` helpers

The two smallest, most-duplicated primitives. Adopt them where the instance matches exactly; leave bespoke avatars (ProfileView's double-ring header) for a follow-up step in this task.

**Files:**
- Modify: `Sources/App/Feed/Components.swift`
- Modify adopters: `FeedPostView.swift`, `NotificationsListView.swift`,
  `ProfileListView.swift`, `SearchView.swift`, `QuoteCardView.swift`,
  `MessagesView.swift`

- [ ] **Step 1: Add `AvatarView` and `relativeTimestamp` to `Components.swift`**

Append to `Sources/App/Feed/Components.swift`:

```swift
/// A circular avatar with the shared placeholder + ring, used everywhere an
/// account image appears so sizing and the hairline ring stay consistent.
struct AvatarView: View {
    let url: URL?
    var size: CGFloat
    var ring = true

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if ring { Circle().strokeBorder(Theme.avatarRing, lineWidth: 0.5) }
        }
    }
}

/// A relative ("2m", "1h") timestamp in the shared meta styling.
@ViewBuilder
func relativeTimestamp(_ date: Date) -> some View {
    Text(date, format: .relative(presentation: .numeric))
        .font(Theme.meta).foregroundStyle(.tertiary).fixedSize()
}
```

- [ ] **Step 2: Regenerate (no new files, but adopters change) and migrate exact-match avatars**

Replace the hand-rolled `AsyncImage { … } placeholder: { … }.frame(…).clipShape(Circle())[.overlay(ring)]` blocks with `AvatarView(url:size:ring:)`:

- `FeedPostView.swift:123-130` → `AvatarView(url: post.avatarURL, size: expanded ? Theme.avatarLarge : Theme.avatar)`
- `NotificationsListView.swift:60-66` → `AvatarView(url: notification.avatarURL, size: 26, ring: false)`
- `ProfileListView.swift:58-65` → `AvatarView(url: profile.avatarURL, size: Theme.avatarSmall)`
- `SearchView.swift:103-108` → `AvatarView(url: profile.avatarURL, size: Theme.avatarSmall)`
- `EmbedViews.swift:75-81` (`QuoteCardView`) → `AvatarView(url: quote.avatarURL, size: 20, ring: false)`
- `MessagesView.swift` row 38-45 → `AvatarView(url: convo.otherAvatarURL, size: 44)`
- `MessagesView.swift` header 124-130 → `AvatarView(url: conversation.otherAvatarURL, size: 30, ring: false)`

`ProfileView.swift:104-112` (74pt double-ring header avatar) is bespoke — leave it.

- [ ] **Step 3: Migrate the three `relativeTimestamp` sites**

Replace `Text(<date>, format: .relative(presentation: .numeric)).font(Theme.meta).foregroundStyle(.tertiary).fixedSize()` with `relativeTimestamp(<date>)`:

- `FeedPostView.swift:156` → `relativeTimestamp(post.date)`
- `NotificationsListView.swift:76` → `relativeTimestamp(notification.date)`
- `MessagesView.swift:52` → `relativeTimestamp(date)`

- [ ] **Step 4: Build**

Run: `./build.sh`
Expected: `==> Built: .../CrossPost.app`, no errors.

- [ ] **Step 5: Test**

Run: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Extract AvatarView and relativeTimestamp helpers"
```

---

## Task 3: `PostBody` component

The canonical rich reading-body. Replaces re-derived `RichText.styled` + tint + lineSpacing + openURL across the reading surfaces.

**Files:**
- Create: `Sources/App/Feed/PostBody.swift`
- Modify adopters: `FeedPostView.swift`, `EmbedViews.swift`, `NotificationsListView.swift`

- [ ] **Step 1: Create `Sources/App/Feed/PostBody.swift`**

```swift
import SwiftUI

/// The canonical reading treatment for a post body: tappable, accent-coloured
/// mentions/links, shared line spacing, in-app link routing, and text selection.
/// Every reading surface (timeline, thread, notifications, quote embed, search,
/// profile) renders through this so they stay consistent.
struct PostBody: View {
    let text: AttributedString
    let accent: Color
    var cacheKey: String?
    var font: Font = Theme.content
    var color: AnyShapeStyle = AnyShapeStyle(.primary)
    var lineLimit: Int?
    let onOpenURL: (URL) -> Void

    var body: some View {
        Text(RichText.styled(text, accent: accent, cacheKey: cacheKey))
            .font(font)
            .foregroundStyle(color)
            .tint(accent)
            .lineSpacing(Theme.bodyLineSpacing)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            // No fixedSize when a line limit is set — they conflict and the text
            // would ignore the limit and grow unbounded.
            .fixedSize(horizontal: false, vertical: lineLimit == nil)
            .environment(\.openURL, OpenURLAction { url in onOpenURL(url); return .handled })
            .textSelection(.enabled)
    }
}
```

- [ ] **Step 2: Regenerate the project (new file)**

Run: `xcodegen generate`
Expected: `Created project at .../CrossPost.xcodeproj`.

- [ ] **Step 3: Adopt in `FeedPostView.swift`**

Replace the `bodyText` body (currently `Text(styledText).font(…).tint(accent).lineSpacing(…).frame(…).fixedSize(…).environment(\.openURL,…).textSelection(.enabled)`, around lines 89-99) with:

```swift
    private var bodyText: some View {
        PostBody(text: post.text, accent: accent, cacheKey: post.id,
                 font: expanded ? Theme.contentLarge : Theme.content,
                 onOpenURL: n)
    }
```

(The `styledText` computed property at lines 83-85 becomes unused — delete it.)

- [ ] **Step 4: Adopt in `EmbedViews.swift`**

Replace the quote-embed body (currently `Text(RichText.styled(quote.text, accent: accent, cacheKey: quote.id)).font(.system(size: 13)).tint(accent).lineLimit(6)`, around line 91) with:

```swift
                PostBody(text: quote.text, accent: accent, cacheKey: quote.id,
                         font: .system(size: 13), lineLimit: 6, onOpenURL: onOpen)
```

(Use the embed's existing link-open closure name; if the embed has no open
handler in scope, pass `onOpenURL: { _ in }` — confirm against the call site.)

- [ ] **Step 5: Adopt in `NotificationsListView.swift`**

Replace the inline rich body added in Task 1 (the `Text(RichText.styled(post.text, …)) … .environment(\.openURL, …)` block) with:

```swift
                if let post = livePost, !post.text.characters.isEmpty {
                    PostBody(text: post.text, accent: accent, cacheKey: post.id,
                             color: bodyIsPrimary ? AnyShapeStyle(.primary)
                                                  : AnyShapeStyle(.secondary),
                             lineLimit: 3,
                             onOpenURL: { model.openLink($0, push: push) })
                }
```

Keep the `bodyIsPrimary` computed property.

- [ ] **Step 6: Build**

Run: `./build.sh`
Expected: `==> Built: .../CrossPost.app`, no errors.

- [ ] **Step 7: Test**

Run: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Extract PostBody for consistent post-body rendering"
```

---

## Task 4: `QuotedPreviewBlock` component

**Files:**
- Create: `Sources/App/Feed/QuotedPreviewBlock.swift`
- Modify: `ReplySheet.swift`, `QuoteSheet.swift`

- [ ] **Step 1: Create `Sources/App/Feed/QuotedPreviewBlock.swift`**

```swift
import SwiftUI

/// The muted reference block shown while composing a reply or quote: an accent
/// rule, the author handle, and a few lines of the post. Intentionally not
/// tappable — it is context, so focus stays on the compose field.
struct QuotedPreviewBlock: View {
    let post: FeedPost
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Capsule().fill(accent.opacity(0.5)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.authorHandle).font(.caption.bold()).foregroundStyle(.secondary)
                Text(post.text).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
            .padding(.leading, 10)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
    }
}
```

- [ ] **Step 2: Regenerate the project (new file)**

Run: `xcodegen generate`
Expected: `Created project at .../CrossPost.xcodeproj`.

- [ ] **Step 3: Adopt in `ReplySheet.swift`**

Replace the block at lines 23-33 (the `HStack` … `.background(RoundedRectangle…)`) with:

```swift
            QuotedPreviewBlock(post: model.post, accent: accent)
```

- [ ] **Step 4: Adopt in `QuoteSheet.swift`**

Replace the `quotedPreview` computed property body at lines 84-96 (the `HStack` … `.background(RoundedRectangle…)`) with:

```swift
    private var quotedPreview: some View {
        QuotedPreviewBlock(post: post, accent: accent)
    }
```

- [ ] **Step 5: Build**

Run: `./build.sh`
Expected: `==> Built: .../CrossPost.app`, no errors.

- [ ] **Step 6: Test**

Run: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Extract QuotedPreviewBlock for reply/quote sheets"
```

---

## Task 5: `ProfileRowView` component

**Files:**
- Create: `Sources/App/Feed/ProfileRowView.swift`
- Modify: `ProfileListView.swift`, `SearchView.swift`

- [ ] **Step 1: Read both existing rows to capture the exact model type and fields**

Run: `sed -n '52,81p' Sources/App/Feed/ProfileListView.swift; echo '---'; sed -n '97,124p' Sources/App/Feed/SearchView.swift`
Use the actual parameter type (e.g. `Profile`) and field names (name/handle/bio) from these rows in Step 2. Do not invent fields.

- [ ] **Step 2: Create `Sources/App/Feed/ProfileRowView.swift`**

Write the component using the type confirmed in Step 1. Template (adjust the
model type and the bio/handle field names to match the real `Profile`):

```swift
import SwiftUI

/// An account list row — avatar, display name, handle, and optional bio — used
/// by the people list and search results so they read identically.
struct ProfileRowView: View {
    let profile: Profile
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(url: profile.avatarURL, size: Theme.avatarSmall)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(Theme.name).lineLimit(1)
                    Text(profile.handle).font(Theme.handle).foregroundStyle(.secondary).lineLimit(1)
                    if !profile.bio.isEmpty {
                        Text(profile.bio).font(Theme.content).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.rowPaddingH).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }
}
```

If the two existing rows differ in any detail (e.g. padding, bio line count),
adopt the timeline/people-list version and apply it to both for consistency.

- [ ] **Step 3: Regenerate the project (new file)**

Run: `xcodegen generate`
Expected: `Created project at .../CrossPost.xcodeproj`.

- [ ] **Step 4: Adopt in `ProfileListView.swift`**

Replace the `row(_:)` function (lines 52-81) and its call site with
`ProfileRowView(profile: profile) { <existing tap action> }`. Preserve whatever
the old row did on tap (push profile route).

- [ ] **Step 5: Adopt in `SearchView.swift`**

Replace `personRow(_:)` (lines 97-124) and its call site with
`ProfileRowView(profile: profile) { <existing tap action> }`.

- [ ] **Step 6: Build**

Run: `./build.sh`
Expected: `==> Built: .../CrossPost.app`, no errors.

- [ ] **Step 7: Test**

Run: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Extract ProfileRowView for people and search lists"
```

---

## Task 6: Sheet chrome (`sheetContainer` + `sheetHeader`)

**Files:**
- Create: `Sources/App/Feed/SheetChrome.swift`
- Modify: `ReplySheet.swift`, `QuoteSheet.swift`, `EditSheet.swift`, `ReportSheet.swift`

- [ ] **Step 1: Create `Sources/App/Feed/SheetChrome.swift`**

```swift
import SwiftUI

extension View {
    /// Standard sheet sizing used by all compose/action sheets.
    func sheetContainer() -> some View {
        padding(20).frame(width: Theme.sheetWidth)
    }
}

/// The header row for a sheet: an accent dot (no icon) or an accent SF Symbol,
/// followed by the title.
@ViewBuilder
func sheetHeader(icon: String?, label: String, accent: Color) -> some View {
    HStack(spacing: 8) {
        if let icon {
            Image(systemName: icon).foregroundStyle(accent)
        } else {
            Circle().fill(accent).frame(width: 9, height: 9)
        }
        Text(label).font(Theme.columnTitle)
    }
}
```

- [ ] **Step 2: Regenerate the project (new file)**

Run: `xcodegen generate`
Expected: `Created project at .../CrossPost.xcodeproj`.

- [ ] **Step 3: Adopt headers and containers**

- `ReplySheet.swift:18-21` → `sheetHeader(icon: nil, label: "Reply on \(model.post.target.displayName)", accent: accent)`; replace `.padding(20).frame(width: Theme.sheetWidth)` (lines 109-110) with `.sheetContainer()`.
- `QuoteSheet.swift:30-33` → `sheetHeader(icon: nil, label: "Quote on \(post.target.displayName)", accent: accent)`; lines 80-81 → `.sheetContainer()`.
- `EditSheet.swift:54-57` → `sheetHeader(icon: "pencil", label: "Edit post", accent: accent)`; lines 85-86 → `.sheetContainer()`.
- `ReportSheet.swift:19-22` → `sheetHeader(icon: "flag", label: "Report \(subjectLabel)", accent: accent)`; lines 59-60 → `.sheetContainer()`.

- [ ] **Step 4: Build**

Run: `./build.sh`
Expected: `==> Built: .../CrossPost.app`, no errors.

- [ ] **Step 5: Test**

Run: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Extract shared sheet container and header chrome"
```

---

## Task 7: Unified `postActionButton`

**Files:**
- Create: `Sources/App/Feed/PostActionBar.swift`
- Modify: `FeedPostView.swift`, `NotificationsListView.swift`

- [ ] **Step 1: Read the three current helpers to confirm exact styling**

Run: `sed -n '298,332p' Sources/App/Feed/FeedPostView.swift; echo '---'; sed -n '138,148p' Sources/App/Feed/NotificationsListView.swift`
Confirm: active colour (`tint` vs `.secondary`), font (`Theme.count` for count,
icon font), and count formatting (`.number.notation(.compactName)`).

- [ ] **Step 2: Create `Sources/App/Feed/PostActionBar.swift`**

Write `postActionButton` to reproduce the confirmed styling. Template:

```swift
import SwiftUI

/// A post action affordance: an SF Symbol, an optional compact count, an active
/// (engaged) tint, and a tooltip. Shared by the timeline and notification rows
/// so reply/repost/like read and behave the same everywhere.
@ViewBuilder
func postActionButton(
    _ symbol: String,
    count: Int? = nil,
    active: Bool = false,
    tint: Color,
    help: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let count, count > 0 {
                Text(count.formatted(.number.notation(.compactName))).font(Theme.count)
            }
        }
        .foregroundStyle(active ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
}
```

Match the exact fonts/sizes found in Step 1; if the timeline icons use a
specific size, add it here so both call sites stay identical.

- [ ] **Step 3: Regenerate the project (new file)**

Run: `xcodegen generate`
Expected: `Created project at .../CrossPost.xcodeproj`.

- [ ] **Step 4: Adopt in `FeedPostView.swift`**

Replace `countAction(...)` (298-319) and `iconAction(...)` (321-332) usages with
`postActionButton(...)` calls (pass `count:` for reply/repost/like, omit it for
plain icons). Delete the now-unused `countAction`/`iconAction` helpers.

- [ ] **Step 5: Adopt in `NotificationsListView.swift`**

Replace the `actionButton(...)` helper (138-148) usages in `actionBar` with
`postActionButton(...)`. Delete the now-unused `actionButton` helper.

- [ ] **Step 6: Build**

Run: `./build.sh`
Expected: `==> Built: .../CrossPost.app`, no errors.

- [ ] **Step 7: Test**

Run: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Unify post action buttons across timeline and notifications"
```

---

## Task 8: Route notifications like/repost through the model (behavior cleanup)

The only behavior change. `NotificationsListView` hand-rolls optimistic
`toggleLike`/`toggleRepost` with local `@State` + rollback; the timeline routes
through `FeedPanelModel`. Move the notifications row to the model path so there is
one source of truth.

**Files:**
- Read: `Sources/App/Feed/FeedPanelModel.swift`, `Sources/App/Feed/FeedPostView.swift`
- Modify: `Sources/App/Feed/NotificationsListView.swift`

- [ ] **Step 1: Identify the model's like/repost entry points**

Run: `rg -n "func .*([Ll]ike|[Rr]epost)" Sources/App/Feed/FeedPanelModel.swift`
Note the exact method names and how `FeedPostView` calls them (it passes
callbacks via `model`). Confirm whether the model exposes a way to toggle a post
referenced by a notification (by post id / record URIs).

- [ ] **Step 2: Verify the optimistic record-URI behavior the local snapshot exists for**

Read `NotificationsListView.swift:38-45` and `toggleLike`/`toggleRepost`
(169-195). The local `post` snapshot holds record URIs across repeated toggles.
Confirm the model path preserves the same record URIs across toggles before
removing the local version. If the model cannot express this for notification
posts, STOP and report — this task may need a model API addition (out of scope
for a pure cleanup; raise it rather than guessing).

- [ ] **Step 3: Replace the local toggles with model calls**

Rewrite `actionBar`'s repost/like buttons to call the model's toggle methods
(the same ones `FeedPostView` uses), removing `toggleLike`, `toggleRepost`,
`mutating`, and the local optimistic `@State` that exists only for them. Keep
`post`/`livePost` only if still needed for display; otherwise remove.

- [ ] **Step 4: Build**

Run: `./build.sh`
Expected: `==> Built: .../CrossPost.app`, no errors.

- [ ] **Step 5: Test**

Run: `xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Visual verification (per project practice)**

Run: `./build.sh --run`
In the Notifications tab: like and unlike a post, repost and undo. Confirm the
glyph state updates optimistically and survives a feed refresh (server truth).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Route notification like/repost through the feed model"
```

---

## Task 9: Final verification sweep

- [ ] **Step 1: Full clean build + test**

Run: `./build.sh && xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS' 2>&1 | tail -5`
Expected: built, `** TEST SUCCEEDED **`.

- [ ] **Step 2: Confirm no dead helpers remain**

Run: `rg -n "styledText|countAction|iconAction|func actionButton|func row\(|func personRow\(" Sources/App/Feed`
Expected: no matches (all replaced by shared components). Any match is leftover dead code — remove it.

- [ ] **Step 3: Visual parity check**

Run: `./build.sh --run`
Walk timeline, thread, notifications, quote embeds, profile + search lists, and
the reply/quote/edit/report sheets. Confirm each renders as before (notifications
body now primary + tappable for mentions/replies).

- [ ] **Step 4: Open PR**

```bash
git push -u origin refactor/shared-feed-components
gh pr create --title "Extract shared feed components" --body "Extracts one source of truth per feed UI concept (PostBody, AvatarView, relativeTimestamp, QuotedPreviewBlock, ProfileRowView, sheet chrome, postActionButton) and routes notification like/repost through the feed model. Fixes notification bodies rendering grey and non-tappable. Pure refactor except the notification body fix and the like/repost model routing."
```
