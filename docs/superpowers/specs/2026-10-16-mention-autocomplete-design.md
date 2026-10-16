# @-mention autocomplete across Mastodon and Bluesky

## Problem

The compose box sends identical text to both networks. Mention syntax does not
cross over:

- Mastodon mentions are `@user@instance`. ATProtoKit's facet parser
  (`ATFacetParser.mentionRegex`) needs a dotted handle preceded by whitespace or
  start of text, so `@user@instance` posts to Bluesky as plain text.
- Bluesky mentions are `@handle.tld`. Mastodon reads `@alice.bsky.social` as a
  nonexistent local username, so it posts as plain text.

A typed `@puppetfather` mentions nobody on Bluesky, and only a local user on
Mastodon.

## Goal

Typing `@` plus a prefix in the compose editor searches both networks. Picking a
person inserts a mention that renders per network at post time. The user can
preview exactly what each network will receive before posting.

## Design

### 1. Data model (Core)

`MentionSpan` (Codable, Sendable, Equatable):

- `range`: UTF-16 offset and length of the mention's visible text in
  `DraftPost.text`.
- `mastodonAcct: String?`: e.g. `puppetfather@hachyderm.io`.
- `blueskyHandle: String?`: e.g. `puppetfather.bsky.social`.
- `displayName: String`.

At least one of `mastodonAcct` / `blueskyHandle` is non-nil.

`DraftPost` gains `mentions: [MentionSpan]` (defaults to `[]`). Drafts persist
through the existing `Codable` path in `DraftStore`. A saved draft without the
key decodes with `mentions == []`.

The visible text in the editor is `@` plus a short name: the Mastodon username
(before the second `@`) when there is a Mastodon account, else the Bluesky
handle with a `.bsky.social` suffix removed (a custom-domain handle such as
`jamesturnbull.net` stays whole).

### 2. Rendering (Core)

`DraftPost.rendered(for: PostTarget) -> DraftPost` replaces each mention's range
with that network's form, processing spans from last to first so earlier
offsets stay valid:

| Network  | Has account on network | No account on network                       |
| -------- | ---------------------- | ------------------------------------------- |
| Mastodon | `@` + `mastodonAcct`   | `displayName`; if blank, the other handle without `@` |
| Bluesky  | `@` + `blueskyHandle`  | `displayName`; if blank, the other handle without `@` |

The rendered `DraftPost` has `mentions == []`.

Bluesky facets come from ATProtoKit's existing `createPostRecord` facet parsing,
which resolves `@handle` to a DID. Known limit: a mention not preceded by
whitespace or start of text (e.g. `(@alice.bsky.social)`) is not linked. A code
comment in `BlueskyPoster` records this.

`CrossPostCoordinator.publish` renders the thread per target before validation
and before handing it to that target's poster. `PostValidator` validates each
target's rendered thread, so a long `@user@instance` counts against Mastodon's
limit and a long Bluesky handle counts against Bluesky's 300.

The compose card's character counter uses the rendered text for each target.

### 3. Editor span tracking (App)

`PlainTextEditor` marks each mention with a custom `NSAttributedString.Key`
whose value identifies the span, and colours it with the accent colour.
`NSTextStorage` moves the attribute with surrounding edits, so the ranges stay
correct without separate offset bookkeeping. After each edit, the coordinator
reads the attribute runs back into `DraftPost.mentions`.

- An edit inside a mention's characters removes that mention (it becomes plain
  text).
- Backspace at the end of a mention deletes the whole mention.
- When the editor is created from a draft, it reapplies the attributes from
  `mentions`.

### 4. Autocomplete popover (App)

- Trigger: `@` at the start of text or after whitespace, followed by at least 2
  characters with no whitespace, caret at the end of that run.
- Debounce 250 ms, cancel the in-flight search on each keystroke.
- Query each selected target with a configured account, concurrently:
  - Bluesky: `searchActorsTypeahead(matching:limit: 8)`.
  - Mastodon: `searchAccounts(params: SearchAccountsParams(query:resolve:), limit: 8)`,
    with `resolve: true` only when the query contains a second `@` (a fully
    qualified address).
- A failure on one network shows the other's results. Both failing shows an
  inline error row in the popover.
- Keyboard: ↑/↓ move, Return/Tab picks, Esc closes. Clicking a row picks it.
- Row: avatar, display name, handle(s), a badge per network.

New Core method on `FeedService`:
`mentionCandidates(matching: String) async throws -> [MentionCandidate]`, where
`MentionCandidate` carries `target`, `handle`, `displayName`, `avatarURL`, and
`profileText` (bio plus Mastodon profile field values, used for merging).

### 5. Merging (Core)

`MentionMerger.merge(mastodon:bluesky:pairs:) -> [MentionPerson]` combines
candidates from one search into rows. Two candidates merge when any holds:

1. The Mastodon candidate's `profileText` contains
   `bsky.app/profile/<bluesky handle>` or `@<bluesky handle>`.
2. The Bluesky candidate's `profileText` contains the Mastodon `@user@instance`
   or the Mastodon profile URL.
3. Bridgy Fed: the Mastodon acct is `<bluesky handle>@bsky.brid.gy`, or the
   Bluesky handle is `<user>.<instance>.ap.brid.gy` for the Mastodon
   `user@instance`.
4. A saved pair matches both handles.

Matching is case-insensitive. Each candidate merges with at most one other.
Unmerged candidates are their own rows.

Manual pairing: right-click a mention in the editor → "Choose Bluesky account…"
(or "Choose Mastodon account…") opens the same search limited to the missing
network. Picking a result fills the span's missing handle and saves the pair to
`mention-pairs.json` in the app's Application Support directory: a JSON array of
`{ "mastodonAcct": "...", "blueskyHandle": "..." }`. The file is plain JSON so it
can be edited by hand or by an agent. A malformed file is logged and treated as
empty. It is not overwritten until the next successful pair save.

### 6. Preview toggle (App)

A segmented control `Edit | Mastodon | Bluesky` in the compose header, listing
only the selected targets. In a network mode every post card in the thread shows
that network's rendered text read-only, with that network's count and limit.
Changing the selected targets resets the mode to Edit if the current network is
deselected. Posting is available in any mode.

## Out of scope

- Autocomplete in the reply composer (`ReplyModel`).
- Building Bluesky facets directly from known DIDs.
- Merging by display name.

## Testing

Core (unit):

- Rendering: both networks, each fallback (display name, blank name), multiple
  mentions, emoji before a mention (UTF-16 offsets).
- `PostValidator` counts rendered text per target, including a mention that
  pushes only Bluesky over its limit.
- Coordinator hands each fake poster its own rendered text.
- `MentionMerger`: each of the four rules, no false merge, one-to-one merging.
- Pair file: round-trip, malformed file reads as empty.
- `DraftPost` decodes a saved draft without `mentions`.

App:

- Editor span tracking via the offscreen `NSWindow` harness: insert text before
  a mention, edit inside a mention, backspace removal, restore from draft.
- Screenshots of the popover and the preview toggle in light and dark mode.
