# CrossPost feature backlog

Gaps found in the 2026-06-15 review of CrossPost against mature Mastodon
(Ice Cubes / Ivory / Mona) and Bluesky (official / Graysky / Skeets) clients.

**Shipped** from the original batch: compose visibility picker, pinned posts on
profile, moderation reporting. **In progress:** bookmarks/likes feeds and
quote-posting.

This file is the **deferred** remainder — to pick up later.

## Deferred from the in-progress batch

Scoped out of the current pass; pick up next.

- [ ] **Polls** — render polls in the feed, vote, and create one when composing.
      Three sub-features; Bluesky has no polls.
- [ ] **Emoji / mention / hashtag autocomplete** — a completion UI over the text
      editor, custom server-emoji fetching, and mention search (depends on the
      Search item below).

## Tier 1 — table stakes

- [ ] **Search** — users, posts, and hashtags. No UI and no service call today
      (the only search code resolves profile URLs internally). Biggest single gap.
- [ ] **Content warnings — read** — reveal row for CW'd Mastodon posts
      (`spoilerText` is already parsed; today the body shows directly).
- [ ] **Content warnings — write** — add a CW when composing.
- [ ] **Sensitive media blur** — blur-until-tapped gate for sensitive media
      (`isSensitive` is already parsed).

## Tier 2 — significant, platform-defining

- [ ] **Bluesky custom feeds** — only the home timeline is available; custom /
      algorithmic feeds are arguably *the* defining Bluesky feature.
- [ ] **Lists (both platforms)** — list timelines and list management.
- [ ] **Hashtag timelines** — tap a hashtag to open its feed; follow hashtags.
- [ ] **Local / federated timelines (Mastodon)** — only Home is offered.

## Tier 3 — compose & power-user polish

- [ ] **Persistent drafts** — multiple drafts that survive a quit (today: one
      in-memory draft).
- [ ] **Scheduled posts.**
- [ ] **GIF / video upload** — display works, but only local images attach today;
      no video upload, no Tenor/Giphy GIF search on compose.
- [ ] **Translation** — a "translate post" action.
- [ ] **Mutes / blocks management** — a list to review/undo mutes and blocks, plus
      muted words / content filters.
- [ ] **Follow-request handling** — approve/deny follows for locked accounts.
- [ ] **Notification filtering / grouping** — per-type filter and grouping
      ("12 people liked…"); today it's a flat list.

## Tier 4 — smaller UX niceties

- [ ] **New-posts indicator** — an "X new posts ▲" pill to jump to top (live
      updates land silently).
- [ ] **Copy link to post** — today only "Open in Browser".
- [ ] **Keyboard navigation** — j/k row movement and shortcuts for
      like/reply/refresh (today only `⌘↩` to post and Esc to dismiss the lightbox).
- [ ] **Appearance settings** — text size, font, and a theme override (today
      follows system light/dark only; also an accessibility consideration).

## Likely deliberate (confirm before building)

Given the app's identity — a focused side-by-side dual-network reader/composer —
these may be intentional scope choices rather than oversights:

- [ ] Multi-account per network.
- [ ] Discovery / trending surfaces.
- [ ] Rich media editing (crop / rotate / filter).
