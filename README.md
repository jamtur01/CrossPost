# crosspost

A simple macOS app to compose a post or thread once and publish it to both
Mastodon and Bluesky, with images, alt text, and per-platform length checks.

## Build

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
xcodegen generate
open Crosspost.xcodeproj   # then ⌘R
```

The `Crosspost.xcodeproj` is generated from `project.yml` and is gitignored —
run `xcodegen generate` after cloning or pulling.

## Test

```bash
xcodebuild test -project Crosspost.xcodeproj -scheme Crosspost -destination 'platform=macOS'
```

## Configure

Open **Settings** (⌘,):
- **Mastodon:** instance URL + access token (on your instance: Preferences →
  Development → New application, scope `write`). Click **Verify & Save Mastodon**.
- **Bluesky:** handle + an app password (bsky.app → Settings → App Passwords).
  Click **Verify & Save Bluesky**.

Credentials are stored in the macOS Keychain; the instance URL and handle live in
app preferences.

## Behavior

- Both platforms are selected by default; toggle either off per send.
- Posts are validated before anything is sent: if any post is empty or exceeds a
  selected platform's limit (Bluesky 300, Mastodon from the instance, default
  500), nothing is posted and the offending post/platform is named.
- Length is counted in grapheme clusters. Mastodon's URL/mention discounting is
  not modeled, so the check is slightly stricter than Mastodon requires.
- Threads link automatically (each post replies to the previous). Platforms are
  independent — if one fails, the other still posts and the per-platform result
  (with links) is shown.
- Images are re-encoded to JPEG under Bluesky's 1 MB per-image limit (max 4 per
  post); each image carries its alt text to both platforms.

## Architecture

- `Sources/Core` — UI-independent logic, unit-tested: models, `PostValidator`,
  `runThread` (thread linking), `CrosspostCoordinator`, `CredentialStore`
  (Keychain), `ImageProcessor`, and the `MastodonPoster`/`BlueskyPoster` adapters
  over [TootSDK](https://github.com/TootSDK/TootSDK) and
  [ATProtoKit](https://github.com/MasterJ93/ATProtoKit).
- `Sources/App` — SwiftUI: the compose window, settings, results sheet, and the
  `AccountStore`/`PosterFactory` glue.
