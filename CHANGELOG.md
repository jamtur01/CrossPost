# Changelog

All notable changes to CrossPost are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.16] - 2026-07-09

### Fixed

- The reply composer now uses the same padding and fixed width as the other
  compose sheets, instead of rendering edge-to-edge and over-wide.

## [0.4.15] - 2026-07-06

### Fixed

- The unread notification badge clears when you open the Notifications tab and
  stays cleared, instead of reappearing the moment you switch away. Opening the
  tab now marks notifications seen as of that moment, matching the Bluesky app.
- The unread count sits on the Notifications tab itself rather than floating
  beside the tab strip, where it looked like it belonged to Messages.

## [0.4.14] - 2026-07-01

### Fixed

- A post with two or more images no longer renders wider than its feed column
  (which clipped the author name, avatar, and text off the left edge).

## [0.4.13] - 2026-06-30

### Added

- Drag image files or drag/paste image data straight into a compose post, and
  drag a post's image out to Finder or another app.
- Keyboard shortcuts to refresh both feeds (Cmd-R) and switch both feeds to
  Home, Notifications, or Messages (Cmd-1/2/3), also in a new View menu.

### Changed

- Like, repost, and reply counts roll when they change, the like/repost glyph
  gives a small bounce, and engagement actions add a trackpad haptic tick.
- Timeline photos lay out as a mosaic grid (one large image, or a two-to-four
  tile grid with a "+N" overflow) instead of a row of fixed thumbnails.
- Feeds show shimmering placeholder rows while the first page loads, and an
  empty feed shows a clear "No posts yet" state.
- Transient errors appear as a floating toast that doesn't shift the layout.
- Wider minimum window size so both feed columns stay legible; unified toolbar
  for a more integrated top bar; deeper card shadows in dark mode.
- Motion-driven effects (toast, scroll-to-top, shimmer) respect the system
  Reduce Motion setting.

## [0.4.12] - 2026-06-30

### Fixed

- Pressing Post or Send twice quickly (or with Cmd-Return) no longer publishes
  the same post or reply more than once.
- After a cross-post that failed partway through a thread, retrying now sends
  only the posts that didn't go through, instead of re-sending ones that already
  landed. Editing an already-published post is refused rather than duplicating it.
- An edited Mastodon post now shows its new text immediately everywhere it
  appears, instead of continuing to show the old text until relaunch.
- Verifying account credentials in Settings now saves exactly the values that
  were checked, even if you keep typing in the fields while it verifies.
- Search no longer briefly shows an error or spinner left over from a previous
  query after you've typed a new one.
- Opening a thread shows the focused post's latest like and repost counts when
  they changed while the thread was loading.
- The pointing-hand cursor no longer occasionally stays stuck after navigating
  away from a profile or image while hovering it.

### Changed

- Followers, following, who-liked, and who-reposted lists (both networks) and
  Bluesky direct-message conversations now load several pages deep instead of
  stopping at the first page.

## [0.4.11] - 2026-06-30

### Fixed

- Notification mentions and replies now render in full-strength text with
  tappable @mentions and links, instead of greyed-out, non-interactive text.

### Changed

- Updated TootSDK to 23.0.0.

## [0.4.10] - 2026-06-16

### Fixed

- Posting several images to Mastodon at once is more reliable — images are now
  processed one at a time before uploading, avoiding an intermittent failure.
- A profile whose pinned posts fail to load now still shows the timeline instead
  of an error.

### Changed

- Tab in the compose box moves to the next control instead of inserting a tab
  character.

### Removed

- The "new posts" indicator pill, which could show a count that didn't match the
  already-updated feed.

## [0.4.9] - 2026-06-16

### Added

- Search people and posts on both networks from a search field in each feed
  header; tap a result to open the profile or thread.
- Choose Mastodon post visibility (public, unlisted, followers-only, or
  mentioned-only) when composing or replying. Replies start at the parent post's
  visibility so a reply never widens its audience.
- Report posts and accounts on both networks, with a reason and optional note.
- Bookmarks and likes feeds, opened from a saved-posts menu in each feed header.
- Quote a post (a Bluesky quote, or a Mastodon quote where the instance supports
  it).
- Edit your own Mastodon posts (text and content warning); media is preserved.
- Pinned posts now show at the top of Mastodon profiles.
- Tap an avatar, banner, or post image to pop it out full-screen; click anywhere
  or press Esc to dismiss.
- A "Copy Link" action on the post menu.
- An "X new posts" pill that appears when new posts arrive while you're scrolled
  down; tap it to jump to the top.

### Fixed

- Profile, thread, and saved-post views now show an error with a Try Again
  button instead of a blank pane when a fetch fails.
- A failed like or repost reliably reverts instead of sticking.
- The unread badge no longer clears if marking notifications read fails on the
  server.
- A pinned post no longer appears twice on a profile.
- The edit and quote character counters use your instance's real limit, and you
  can't save an over-limit edit.
- An unreadable image is caught before posting, so it can't fail partway through
  a thread and strand earlier posts.
- Posts from some servers no longer lose their line breaks.

### Changed

- The compose, reply, edit, quote, and report sheets take Cmd-Return to submit
  and Esc to cancel.
- Empty and error states, list-row hover, and the editor sheets share a more
  consistent look.

## [0.4.8] - 2026-06-14

### Added

- Post text in the timeline is now selectable, so you can copy from a post
  without opening it first.

### Fixed

- The unread notification badge now updates when you return to the app and when
  you refresh manually, not only on the timed background poll. A notification
  that arrived while the app was in the background — common on Bluesky, which
  has no live stream — no longer stays hidden until the next poll or relaunch.

### Changed

- The feed and notification badge refresh every 30 seconds (was 60).

## [0.4.7] - 2026-06-13

### Added

- Notification rows show whether you already follow someone, so the Follow
  button reflects real state instead of always reading "Follow."
- Non-public Mastodon posts (unlisted, followers-only, direct) show a small
  indicator next to the timestamp.

### Fixed

- Bluesky errors now show a readable message instead of "ATAPIError error 0,"
  and a failed refresh no longer leaves a red banner stuck over the feed.
- Bookmark, pin, and like/repost counts now update immediately in thread and
  profile views instead of waiting for the next reload.
- Failed direct messages and failed follow/mute/block actions now show an
  error instead of silently doing nothing.
- Overlong image alt text is caught before posting instead of failing
  mid-upload and splitting a thread across networks.

### Changed

- Bluesky image uploads may now be up to 2 MB (raised from 1 MB), matching
  Bluesky's current limit, so images are compressed less aggressively.

## [0.4.6] - 2026-06-12

### Fixed

- Opening a reply now places the cursor after the prefilled @mentions
  instead of before them.

## [0.4.5] - 2026-06-10

### Fixed

- Posts heavy in emoji or other multi-byte text that fit Bluesky's
  300-character limit but exceed its 3,000-byte limit are now caught before
  posting, instead of publishing to Mastodon and then failing on Bluesky.
- Switching accounts no longer risks feeds quietly continuing to use a
  connection for the previous account when the change happens mid-load.

### Changed

- Posts publish to Mastodon and Bluesky at the same time instead of one
  after the other, and images upload concurrently, so cross-posts with media
  complete in roughly half the time.
- Feeds, notifications, profiles, and direct messages make fewer sequential
  network requests, and post rendering caches work it used to repeat.

### Security

- Mastodon instance URLs must use HTTPS so the access token can't be sent in
  cleartext; plain HTTP remains allowed only for localhost dev instances.

## [0.4.4] - 2026-06-08

### Added

- Reply, repost, like, and follow actions directly on notification rows.
- A direct-message conversation header that opens the other person's profile,
  and a timestamp under each message.

### Fixed

- Bluesky reposts no longer vanish from feeds and now show a "reposted by"
  attribution.
- Posts quoting an account you've blocked or muted are no longer shown.
- An over-limit or failed reply no longer reports "Reply sent" and loses the
  draft.
- The follow button on notifications can no longer accidentally unfollow
  someone you already follow.
- Like and repost counts update immediately in the timeline, matching the
  notification rows.
- Editing a post's text no longer moves the cursor to the start, and the
  composer leaves in-progress input-method composition alone.
- Images that can't be read when attaching now surface an error instead of
  being silently dropped.

### Changed

- Feeds, profiles, and notifications fetch the same content more completely,
  and the Bluesky handle is normalized so your own posts are recognized
  regardless of how you typed it at sign-in.

## [0.4.3] - 2026-06-08

### Added

- The app's dock icon shows a badge with the total number of unread
  notifications across both networks.

## [0.4.2] - 2026-06-07

### Added

- The App Sandbox is now enabled, containing the app with only the
  network-client and user-selected-file entitlements it needs.

### Changed

- Release builds stamp their version from the git tag, so a build reports the
  version it actually shipped as.
- Links in posts, profile bios, and richtext only open `http`/`https` URLs;
  other schemes (`file://`, custom app schemes) are no longer tappable.
- Feeds, profiles, and the notification list fetch several pages deep at each
  platform's maximum page size, instead of a single short page.
- Credentials are stored in the Keychain as this-device-only.

### Fixed

- Like, repost, and delete failures in thread and profile views now surface an
  error and roll back, instead of failing silently.
- A target that already received the current post is locked until the post is
  edited, so a partly-failed cross-post can't be duplicated by posting again.
- Switching feed columns no longer briefly shows the previous column's
  notifications or messages.
- Animated GIFs are bounded in memory and oversized downloads are skipped.

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

[0.4.16]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.16
[0.4.15]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.15
[0.4.8]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.8
[0.4.7]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.7
[0.4.6]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.6
[0.4.5]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.5
[0.4.4]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.4
[0.4.3]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.3
[0.4.2]: https://github.com/jamtur01/CrossPost/releases/tag/v0.4.2
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
