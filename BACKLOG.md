# CrossPost feature backlog

Gaps found in the 2026-06-15 review of CrossPost against mature Mastodon
(Ice Cubes / Ivory / Mona) and Bluesky (official / Graysky / Skeets) clients.

This file is the remaining work — to pick up later.

## Shipped

- [x] **Compose visibility picker** — Mastodon public/unlisted/followers/direct,
      on compose and replies (replies seed from the parent).
- [x] **Pinned posts** — surfaced on Mastodon profiles.
- [x] **Moderation reporting** — report posts and accounts on both networks.
- [x] **Bookmarks & likes feeds** — saved-posts menu in each feed header.
- [x] **Quote posting** — embed a post on its own network.
- [x] **Post editing** — edit your own Mastodon posts (text + content warning).
- [x] **Search** — people and posts on both networks, from a header search field.
- [x] **Copy link to post** — on the post menu.

## Deferred — larger efforts

Consciously scoped out for size; pick up next.

- [ ] **Polls** — render polls in the feed, vote, and create one when composing.
      Three sub-features; Bluesky has no polls.
- [ ] **Emoji / mention / hashtag autocomplete** — a completion UI over the text
      editor, custom server-emoji fetching, and mention lookup (the search service
      now exists to back it).

## Tier 1 — table stakes

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

- [ ] **Appearance settings** — text size, font, and a theme override (today
      follows system light/dark only; also an accessibility consideration).

## Likely deliberate (confirm before building)

Given the app's identity — a focused side-by-side dual-network reader/composer —
these may be intentional scope choices rather than oversights:

- [ ] Multi-account per network.
- [ ] Discovery / trending surfaces.
- [ ] Rich media editing (crop / rotate / filter).
