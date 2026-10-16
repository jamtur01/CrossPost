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
offsets stay valid. A span outside the text is skipped; the editor (section 3)
keeps spans in step with the text, so rendering does not re-check the visible
text:

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

The compose card's character counter counts each selected target's rendered
text the way that target's server does (`PostValidator.countedGraphemes`) and
shows the target with the least room left, labelled with its name, or "Both
networks" on a tie. This replaces `characterLimit` / `limitingNetwork`.

Landed-post signatures (`PostSignature`, used to detect edits to an
already-published thread prefix) are taken from each target's rendered post, so
re-pointing a mention at a different account counts as an edit on that network.

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

### 4. Autocomplete suggestions (App)

- Trigger: `@` at the start of text or after whitespace, followed by at least 2
  characters with no whitespace, caret at the end of that run.
- Debounce 250 ms, cancel the in-flight search on each keystroke.
- Query each selected target with a configured account, concurrently:
  - Bluesky: `searchActorsTypeahead(matching:limit: 8)`. This returns
    `ProfileViewBasic`, which has no bio, so Bluesky candidates carry no
    profile text.
  - Mastodon: `searchAccounts(params: SearchAccountsParams(query:resolve:), limit: 8)`,
    with `resolve: true` only when the query contains a second `@` (a fully
    qualified address).
- A failure on one network shows the other's results. No results plus a failure
  shows an inline error row.
- The suggestions appear as a list inside the post card, directly under the
  editor, while a query is active. The text view keeps keyboard focus.
- Keyboard: ↑/↓ move, Return/Tab picks, Esc closes. Clicking a row picks it.
- Row: avatar, display name, handle(s), a badge per network.
- Picking inserts the visible text plus a trailing space and moves the caret
  after it.
- No query is detected while the caret is directly after an existing mention.

New Core method on `FeedService`:
`mentionCandidates(matching: String) async throws -> [MentionCandidate]`, where
`MentionCandidate` carries `target`, `handle`, `displayName`, `avatarURL`, and
`profileText` (bio plus Mastodon profile field values, used for merging).

### 5. Merging (Core)

`MentionMerger.merge(mastodon:bluesky:pairs:) -> [MentionPerson]` combines
candidates from one search into rows. Two candidates merge when any holds:

1. The Mastodon candidate's `profileText` (bio plus profile field values)
   contains `bsky.app/profile/<bluesky handle>` or `@<bluesky handle>`, not
   followed by a letter, digit or `-`.
2. Bridgy Fed: the Mastodon acct is `<bluesky handle>@bsky.brid.gy`, or the
   Bluesky handle is `<user>.<instance>.ap.brid.gy` for the Mastodon
   `user@instance`.
3. A saved pair matches both handles.

The reverse check (a Bluesky bio naming the Mastodon account) is not possible:
typeahead results carry no bio.

Matching is case-insensitive. Each candidate merges with at most one other.
Unmerged candidates are their own rows. Rows alternate Mastodon-first and
Bluesky-first results in their original order. After merging, a single-network
row whose handle appears in a saved pair gets the paired handle filled in, so a
saved pair applies even when the other network's search did not return that
account.

Manual pairing: right-click a mention in the editor → "Choose Bluesky account…"
(or "Choose Mastodon account…") opens a sheet with a search field and results
from the missing network only, prefilled with the person's display name. Picking a result fills the span's missing handle and saves the pair to
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
- Query detection: start of text, after whitespace, too short, email-like,
  full `@user@instance`, caret mid-word.
- `PostValidator` counts rendered text per target, including a mention that
  pushes only Bluesky over its limit.
- Coordinator hands each fake poster its own rendered text.
- `MentionMerger`: each rule, no false merge, one-to-one merging, saved pair
  completing a single-network row.
- Pair file: round-trip, malformed file reads as empty.
- `DraftPost` decodes a saved draft without `mentions`.

App:

- Editor span tracking via the offscreen `NSWindow` harness: insert text before
  a mention, edit inside a mention, backspace removal, restore from draft.
- `MentionCompletion`: debounced search, stale results discarded, failure row,
  selection wraps.
- Compose model: counter per rendered target, preview reset on deselect,
  pairing updates the span and saves the pair.
- Screenshots of the suggestion list and the preview toggle in light and dark
  mode.
