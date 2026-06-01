# crosspost — Design Spec

**Date:** 2026-06-01
**Status:** Approved

## Summary

A small SwiftUI **macOS app** that composes a post or thread once and publishes
it to both Mastodon and Bluesky simultaneously. The app has two windows: a
**Compose** window (thread composer + per-target toggles) and a **Settings**
window (account credentials).

## Confirmed Decisions

| Decision | Choice |
|----------|--------|
| Platform | SwiftUI macOS app (not a CLI) |
| Packaging | Xcode project (`.xcodeproj`), built/tested via `xcodebuild` |
| Bluesky SDK | [ATProtoKit](https://github.com/MasterJ93/ATProtoKit) (pin exact version — pre-1.0) |
| Mastodon SDK | [TootSDK](https://github.com/TootSDK/TootSDK) |
| Scope | Text + images (with alt text) + threads (full thread composer in v1) |
| Targets | Both on by default; per-target toggles to narrow |
| Bluesky auth | App password (handle + app password) |
| Secret storage | macOS Keychain for tokens; UserDefaults for non-secret prefs |
| Length handling | Validate all posts; **abort entirely** if any post exceeds any selected target's limit |

## Architecture

```
CrosspostApp (SwiftUI @main)
├── Compose window
│   ├── ThreadComposerView      ── list of PostCardView (text + images + alt text)
│   ├── TargetToggles           ── Mastodon ✓  Bluesky ✓ (both on by default)
│   └── Post button → ResultsSheet
└── Settings window
    └── SettingsView            ── Mastodon (instance URL, access token)
                                   Bluesky (handle, app password)
                                   "Verify" buttons per account

Core (UI-independent, unit-tested)
├── Models:   DraftPost, Attachment(altText), PostTarget, PostResult
├── Poster (protocol): post(thread:) async throws -> [PostResult]
│     ├── MastodonPoster  (wraps TootSDK)
│     └── BlueskyPoster   (wraps ATProtoKit)
├── CrosspostCoordinator   ── validate → fan out to selected Posters → aggregate
├── PostValidator          ── pure: grapheme counts vs per-target limits
└── CredentialStore        ── Keychain (secrets) + UserDefaults (instance URL, handle)
```

The two SDKs sit behind a `Poster` protocol, so the coordinator, validator, and
thread-linking logic are testable without network access.

## Models

- `DraftPost` — `text: String`, `attachments: [Attachment]`
- `Attachment` — image data + `altText: String`
- `PostTarget` — enum: `.mastodon`, `.bluesky`
- `PostResult` — `target: PostTarget`, success (with post URL) or failure (with error)
- Account config — Mastodon instance URL + access token; Bluesky handle + app
  password. Non-secret fields in UserDefaults; secrets in Keychain.

## Data Flow — Posting a Thread

1. User writes N post cards, attaches images (each with alt text), selects
   targets, presses **Post**.
2. **Validate (abort-on-fail):** for every post × every selected target, check
   grapheme count. Bluesky = 300; Mastodon = the instance's `max_toot_chars`
   (fetched at verify-time, fallback 500). If *any* post exceeds *any* selected
   limit, stop and show exactly which post/platform is over. Nothing is sent.
3. **Publish** per target, sequentially within a thread:
   - **Mastodon:** upload media → post first status → each subsequent status as
     `in_reply_to_id` of the previous.
   - **Bluesky:** upload image blobs → create first record (capture `uri`+`cid`
     as root) → each subsequent record carries `reply: {root, parent}`. RichText
     facets (links/mentions) parsed via ATProtoKit's helper.
4. **Results sheet:** per-target ✓ with post URL, or ✗ with the error. Targets
   are independent — Mastodon may succeed while Bluesky fails; that partial state
   is reported clearly, including which posts in a thread landed.

### Known Simplification

Mastodon weights URLs as 23 characters and ignores mention domains in its length
count; v1 counts raw graphemes, which is stricter. This never *under*-counts, so
it will never let a too-long post through — at worst it flags a borderline post
that Mastodon would have accepted. Documented in code; refine later if needed.

## Error Handling

- **Settings "Verify"** surfaces auth problems immediately (bad token, wrong
  instance, invalid app password) before composing.
- **Validation** blocks the whole send with an actionable message (which post,
  which platform, count vs. limit).
- **Posting** errors are caught per target and shown in the results sheet — never
  silently swallowed. Mid-thread failure reports which posts landed (with links).

## Testing

- `PostValidator` — pure grapheme counting incl. emoji/CJK, boundary cases
  (exactly at limit, empty post), multi-target.
- Thread-linking — Mastodon reply chains and Bluesky `root/parent` refs, with
  `Poster` SDK calls mocked behind protocols.
- `CrosspostCoordinator` — target selection, partial-failure aggregation,
  abort-on-validation.
- `CredentialStore` — round-trip save/load/delete against Keychain.
- UI kept thin; logic lives in the tested Core layer.

## Out of Scope (v1)

- OAuth for Bluesky (using app password instead)
- Platforms beyond Mastodon and Bluesky
- Scheduling, drafts persistence, post editing/deletion
- Accurate Mastodon URL/mention length weighting (see Known Simplification)
- Multiple accounts per platform

## Noted Tension

A "very simple graphical app" plus a full thread composer are in mild tension —
the thread composer is the most complex single piece of the app. Retained per
user approval.
