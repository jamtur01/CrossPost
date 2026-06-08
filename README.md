# CrossPost

A native macOS app for reading and posting to **Mastodon** and **Bluesky** side by
side. It opens into three columns — a composer plus a live feed for each network —
so you can write once and publish to both, and reply to, like, or repost individual
posts without leaving the window.

<img width="2888" height="1816" alt="Screenshoot 2026-06-07 at 20 09 43@2x" src="https://github.com/user-attachments/assets/11017e4e-2ef0-49a9-8963-51cf14453dba" />

## Features

- **Three-column window** — Compose · Mastodon · Bluesky, with draggable dividers.
- **Cross-post** a single post or a whole thread to both networks at once, with
  images (and alt text). Posts are validated first: if anything is empty or over a
  network's limit (Bluesky 300, Mastodon from your instance), nothing is sent and
  the offending post/network is named.
- **Feeds** per network with **Home**, **Notifications**, and (Bluesky) **Messages**
  tabs. Mastodon refreshes live over its streaming socket; both poll (~60s) and
  refresh manually. The notification tab carries an unread badge.
- **Per-post actions** — reply (scoped to that one network), like/favourite,
  repost/boost, bookmark, delete and pin your own posts, see who liked or reposted,
  and open the original in your browser.
- **Rich rendering** — inline images, animated GIFs and video, link preview cards,
  quoted posts, and clickable links and mentions. Boosts/reposts show a "boosted by"
  attribution.
- **In-app profiles & threads** — tap an avatar, mention, or profile link to open a
  profile or expand a thread in place, with followers/following lists.
- **Social graph** — follow/unfollow, mute, and block from a profile.
- **Direct messages** — read and send Bluesky DMs in the Messages tab.
- **Sandboxed**, Developer ID-signed and notarized. Credentials are stored in the
  **macOS Keychain** (this-device-only); instance URL and handle live in app
  preferences.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (`brew install xcodegen`) to build from source

## Build & run

The Xcode project is generated from `project.yml`, so generate it first:

```bash
xcodegen generate
open CrossPost.xcodeproj   # then ⌘R
```

Or build a standalone app bundle into `build/CrossPost.app`:

```bash
./build.sh          # build only
./build.sh --run    # build, then launch
./build.sh --release
```

`CrossPost.xcodeproj` and `build/` are gitignored — regenerate after cloning.

## Configure accounts

Open **Settings** (⌘,):

- **Mastodon** — your instance URL (a bare host like `hachyderm.io` is fine; the
  scheme is added for you) and an access token. Create the token on your instance
  under **Preferences → Development → New application** with the **`read`** and
  **`write`** scopes, then copy "Your access token". Click **Verify & Save**.
- **Bluesky** — your handle (e.g. `you.bsky.social`) and an **app password**
  (bsky.app → **Settings → Privacy and security → App passwords**), *not* your main
  password. Click **Verify & Save**.

A network without saved credentials shows a "Connect in Settings" prompt instead of
a feed.

## Using it

- **Compose** (left column): type a post; **Add post to thread** stacks more posts
  inline; attach images with alt text. Toggle **Mastodon** / **Bluesky** (both on by
  default) and press **Post** (⌘↩). On success the box clears and the feed columns
  you posted to refresh — no popup. Per-network failures show inline; a target that
  already received the current post is locked until you edit it, so a partial
  cross-post can't be sent twice.
- **Feeds** (middle/right): switch **Home** / **Notifications** / **Messages**,
  refresh, and on any post use **reply**, **like**, **repost**, **bookmark**, or the
  overflow menu (**delete**/**pin** your own, **open in browser**, who liked or
  reposted). Replies open a sheet scoped to that network only. Tap an avatar,
  mention, or profile link to open a profile or thread in place.

### Behavior notes

- Length is counted in grapheme clusters. Mastodon's URL/mention discounting isn't
  modeled, so the check is slightly stricter than Mastodon requires.
- Threads link automatically (each post replies to the previous).
- Networks are independent — if a post fails on one, the other still goes through.
- Bluesky images are re-encoded to JPEG under the 1 MB per-image limit (max 4);
  Mastodon allows up to 10 MB.
- Feeds, profiles, and notifications are fetched several pages deep at each
  platform's maximum page size.
- Only `http`/`https` links are tappable; other schemes from remote content are
  rendered as plain text.

## Architecture

- `Sources/Core` — UI-independent, unit-tested logic: models, `PostValidator`,
  `runThread` (thread linking), `CrossPostCoordinator`, `CredentialStore` (Keychain),
  `ImageProcessor`, and the `MastodonPoster`/`BlueskyPoster` adapters.
- `Sources/Core/Feed` — feed logic: the SDK-free `FeedPost`/`FeedNotification`/
  `Conversation` models, the `FeedService` adapters over both SDKs (feeds,
  notifications, DMs, social graph, post management), and the unit-tested
  `HTMLRenderer`, `RichTextLinks`, `WebLink`, `FeedMerge`, and `BlueskyThreadRef`
  helpers.
- `Sources/App` — SwiftUI: the three-column `MainView`, feed panels with in-place
  navigation (post cards, threads, profiles, notifications, messages, media players),
  reply sheet, the compose column, settings, and the
  `AccountStore`/`PosterFactory`/`FeedServiceFactory` glue.

The app runs in the App Sandbox (`CrossPost.entitlements`). Built on
[TootSDK](https://github.com/TootSDK/TootSDK) (Mastodon) and
[ATProtoKit](https://github.com/MasterJ93/ATProtoKit) (Bluesky). The app icon is
generated by `scripts/make_app_icon.swift`.

## Tests

```bash
xcodebuild test -project CrossPost.xcodeproj -scheme CrossPost -destination 'platform=macOS'
```

## Continuous integration & releases

**CI** (`.github/workflows/ci.yml`) builds and runs the tests on every push to
`main` and on pull requests.

**Releases** (`.github/workflows/release.yml`) trigger on `v*` tags: they build an
Apple Silicon Release bundle, stamp its version from the tag, **code-sign it with a
Developer ID and notarize it with Apple**, then publish a GitHub Release whose notes
are taken from the matching `CHANGELOG.md` section, with a notarized DMG and a
zip of the app attached.

### Cutting a release

1. **Add a `CHANGELOG.md` entry** for the new version, e.g. `## [0.4.3] - 2026-06-08`,
   following [Keep a Changelog](https://keepachangelog.com/) (Added / Changed / Fixed),
   and add its link reference at the bottom of the file. This is **required**: the
   release workflow fails fast if the tag has no matching changelog section.
2. Commit and push to `main`.
3. Tag and push (the tag must be `v` + the changelog version):

   ```bash
   git tag v0.4.3
   git push origin v0.4.3
   ```

The workflow builds, signs, notarizes, and publishes the release with notes from the
changelog. The bundle's `MARKETING_VERSION` is set from the tag, so it reports the
version it shipped as — no manual `project.yml` bump needed for releases.

To rewrite **existing** releases' notes after editing `CHANGELOG.md`, run the
**Sync Release Notes** workflow (`.github/workflows/sync-release-notes.yml`) from the
Actions tab.

Signing/notarization requires these repository secrets: `MACOS_CERTIFICATE_P12`,
`MACOS_CERTIFICATE_PASSWORD`, `MACOS_CODESIGN_IDENTITY`, `APPLE_ID`,
`MACOS_API_ISSUER_ID` (your Developer Team ID), and `APPLE_APP_SPECIFIC_PASSWORD`.

## License

[MIT](LICENSE) © James Turnbull
