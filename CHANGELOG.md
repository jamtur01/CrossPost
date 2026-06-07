# Changelog

All notable changes to CrossPost are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-06-07

### Fixed

- Compose footer layout: the Post button is now a full-width button with the
  Mastodon and Bluesky target pills centered above it, instead of being
  squeezed to a sliver in the narrow compose column.

## [0.4.0] - 2026-06-07

### Added

- Social graph: follow and unfollow, mute and block, and followers/following
  lists for any profile.
- Notifications tab with an unread badge, covering mentions, replies, likes,
  reposts, follows, and quotes.
- Follow back from a notification, and open a profile by tapping its avatar in
  the notifications list.
- Post management and engagement: delete your own posts, bookmark, pin and
  unpin (Mastodon), and view who liked or reposted a post.
- Bluesky direct messages, including a conversation list and inline composer.
- Live Mastodon streaming so feeds refresh as new posts arrive.
- Inline playback of animated GIFs and video in feeds.

### Changed

- Refreshed visual design across feeds and compose.
- Profile bio links now route through the in-app profile handler instead of the
  browser.
- Only genuine links are colored in post and bio text; plain `@text` is no
  longer styled as a link.

### Fixed

- Bluesky follow now works (it was sending a handle where a DID was required).
- Navigating from one profile straight to another now reloads the view.
- Off-screen GIF and video playback is paused so it no longer decodes in the
  background.
- Notifications are marked read only up to the newest item you have seen, so a
  notification that arrives after the list loads is not silently marked read.
- DM conversation list refreshes after sending, and a conversation's unread dot
  clears when it is opened.

## [0.3.5] - 2026-06-05

### Added

- Bluesky richtext facets resolve into clickable links.

## [0.3.4] - 2026-06-05

### Changed

- Profile links open in-app instead of launching the browser.

## [0.3.3] - 2026-06-05

### Fixed

- Test runs use an isolated UserDefaults suite, so running the test suite no
  longer wipes real app settings.

## [0.3.2] - 2026-06-05

### Added

- App-layer tests (the test target is now `CrossPostTests`).

### Changed

- Bluesky replies no longer prefill an `@mention`, and refreshing a feed snaps
  it back to the top.

### Fixed

- Unit tests no longer prompt for the Keychain password.

## [0.3.1] - 2026-06-05

### Fixed

- Mastodon mentions and links render as clickable links rather than
  `label (url)` text.

## [0.3.0] - 2026-06-05

### Added

- Redesigned feed and compose UI with per-platform accent colors and native
  window chrome.
- In-app profiles and thread navigation, with a pop-out post detail view.
- Link and quote cards, including pulled quote images.
- Bluesky mentions are hydrated to show their images, cards, and quotes.
- Engagement counts and styled, clickable links on posts.
- App version shown in Settings.

### Changed

- The two feed columns are now equal width.

### Fixed

- Duplicate boost IDs, partial cross-post failures, and image MIME handling.

## [0.2.1] - 2026-06-02

### Added

- Reply-context view showing the post you are replying to.
- Replies prefill the author's `@mention` (and other participants, excluding
  yourself) so they post as real replies.

### Fixed

- Duplicate cross-posts when retrying after a partial failure.
- Optimistic action reverts, refresh/column-switch state, and preservation of
  unknown post visibility.

## [0.2.0] - 2026-06-02

### Changed

- Renamed the app to CrossPost and added an MIT license.
- Updated CI actions to the Node 24 runtime.

## [0.1.0] - 2026-06-02

Initial release.

### Added

- Three-column layout: compose on the left, with Mastodon and Bluesky feeds
  side by side.
- Cross-post to Mastodon and Bluesky at once, with per-target length validation
  and image attachments fitted under each platform's byte budget.
- Inline thread composer for posting a chain of posts.
- Read feeds with boost/repost attribution, reply inline, and optimistic
  like/repost actions.
- Mastodon (TootSDK) and Bluesky (ATProtoKit) service adapters.
- Keychain-backed credential storage.
- Signed and notarized Developer ID release builds produced by CI.

[0.4.1]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.1
[0.4.0]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.0
[0.3.5]: https://github.com/jamtur01/CrossPost/releases/tag/v0.3.5
[0.3.4]: https://github.com/jamtur01/CrossPost/releases/tag/v0.3.4
[0.3.3]: https://github.com/jamtur01/CrossPost/releases/tag/v0.3.3
[0.3.2]: https://github.com/jamtur01/CrossPost/releases/tag/v0.3.2
[0.3.1]: https://github.com/jamtur01/CrossPost/releases/tag/v0.3.1
[0.3.0]: https://github.com/jamtur01/CrossPost/releases/tag/v0.3.0
[0.2.1]: https://github.com/jamtur01/CrossPost/releases/tag/v0.2.1
[0.2.0]: https://github.com/jamtur01/CrossPost/releases/tag/v0.2.0
[0.1.0]: https://github.com/jamtur01/CrossPost/releases/tag/v0.1.0
