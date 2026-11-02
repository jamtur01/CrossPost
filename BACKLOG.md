# CrossPost feature backlog

Gaps found in the 2026-06-15 review of CrossPost against mature Mastodon
(Ice Cubes / Ivory / Mona) and Bluesky (official / Graysky / Skeets) clients.

This file is the remaining work — to pick up later.

## Shipped

- [x] **Compose visibility picker** — Mastodon public/unlisted/followers/direct,
      on compose and replies (replies seed from the parent).
- [x] **Pinned posts** — surfaced on Mastodon profiles.
- [x] **Moderation reporting** — report posts and accounts on both networks.
- [x] **Bookmarks & likes feeds** — saved-posts menu in each feed header, on both
      networks, loading older posts as you scroll.
- [x] **Quote posting** — embed a post on its own network.
- [x] **Post editing** — edit your own Mastodon posts (text + content warning).
- [x] **Search** — people and posts on both networks, from a header search field.
- [x] **Copy link to post** — on the post menu.
- [x] **Active draft recovery** — one draft and its safe retry progress survive a quit.
- [x] **Reading text size** — Standard, Larger, and Largest in Settings.
- [x] **Mention autocomplete** — `@` searches both networks (v0.5.0).
- [x] **Keyboard navigation** — every feed list, the composer, and messages, with
      Help › Keyboard Shortcuts.
- [x] **New-posts pill** — Home keeps your place when posts arrive above you.
- [x] **Recent Posts** — CrossPost sends with per-network counts in the composer.
- [x] **Delete confirmation** and **Try Again** on failed loads.

## Deferred — larger efforts

Consciously scoped out for size; pick up next.

- [ ] **Polls** — render polls in the feed, vote, and create one when composing.
      Three sub-features; Bluesky has no polls.
- [ ] **Emoji / hashtag autocomplete** — custom server-emoji fetching and hashtag
      completion over the text editor; mention autocomplete has shipped.
- [ ] **Own cross-posts shown once** — a send's two network copies as one timeline
      entry with both networks' counts. Deferred 2026-11-01; Recent Posts in the
      composer covers the counts for now.
- [ ] **Unified notifications** — one place for both networks' notifications
      instead of a bell per column.

## Tier 1 — table stakes

- [x] **Content warnings — read** — reveal row for CW'd Mastodon posts, Bluesky
      `!warn` / `!hide` labels, quoted posts, and notification previews.
- [ ] **Content warnings — write** — add a CW when composing.
- [x] **Sensitive media blur** — blur-until-clicked gate for sensitive media,
      Bluesky adult and graphic media labels, and link card thumbnails.

## Tier 2 — significant, platform-defining

- [ ] **Bluesky custom feeds** — only the home timeline is available; custom /
      algorithmic feeds are arguably *the* defining Bluesky feature.
- [ ] **Lists (both platforms)** — list timelines and list management.
- [ ] **Hashtag timelines** — tap a hashtag to open its feed; follow hashtags.
- [ ] **Local / federated timelines (Mastodon)** — only Home is offered.

## Tier 3 — compose & power-user polish

- [ ] **Multiple drafts** — save and choose between several drafts (today: one
      active draft is saved across quits).
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

- [ ] **Appearance settings** — font selection and a theme override (today
      follows system light/dark; reading text size is available).

## Likely deliberate (confirm before building)

Given the app's identity — a focused side-by-side dual-network reader/composer —
these may be intentional scope choices rather than oversights:

- [ ] Multi-account per network.
- [ ] Discovery / trending surfaces.
- [ ] Rich media editing (crop / rotate / filter).
