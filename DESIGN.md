---
name: CrossPost
description: A native Mac switchboard for reading and posting to Mastodon and Bluesky side by side.
colors:
  mastodon-blurple: "#6364FF"
  bluesky-blue: "#0A7AFF"
  system-accent: "AccentColor"
  like-pink: "#FF2D55"
  repost-green: "#34C759"
  danger-red: "#FF3B30"
  warning-orange: "#FF9500"
  surface: "#FFFFFF"
  label-primary: "rgba(0, 0, 0, 0.85)"
  label-secondary: "rgba(0, 0, 0, 0.5)"
  hairline: "rgba(0, 0, 0, 0.07)"
  hover-fill: "rgba(0, 0, 0, 0.04)"
  placeholder-fill: "rgba(0, 0, 0, 0.06)"
  avatar-ring: "rgba(0, 0, 0, 0.08)"
typography:
  column-title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 600
  column-subtitle:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 500
  name-large:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "16px"
    fontWeight: 600
  name:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "14px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "14px"
    fontWeight: 400
  body-detail:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 400
  body-expanded:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "18px"
    fontWeight: 400
  meta:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12.5px"
    fontWeight: 400
  context:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 500
  count:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12.5px"
    fontWeight: 400
    fontFeature: "tnum"
  label:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 500
rounded:
  xs: "4px"
  sm: "8px"
  md: "10px"
  lg: "12px"
  bubble: "15px"
  full: "9999px"
spacing:
  component: "6px"
  gutter: "10px"
  row: "14px"
  row-wide: "16px"
  action-gap: "20px"
  sheet: "20px"
components:
  timeline-row:
    backgroundColor: "transparent"
    textColor: "{colors.label-primary}"
    typography: "{typography.body}"
    padding: "10px 14px"
  timeline-row-hover:
    backgroundColor: "{colors.hover-fill}"
  column-header:
    textColor: "{colors.label-primary}"
    typography: "{typography.column-title}"
    padding: "0 14px"
    height: "52px"
  button-post:
    backgroundColor: "{colors.system-accent}"
    textColor: "#FFFFFF"
    height: "28px"
  target-pill-mastodon-selected:
    backgroundColor: "rgba(99, 100, 255, 0.10)"
    textColor: "{colors.label-primary}"
    rounded: "{rounded.full}"
    padding: "6px 8px"
  target-pill-unselected:
    backgroundColor: "{colors.hover-fill}"
    textColor: "{colors.label-primary}"
    rounded: "{rounded.full}"
    padding: "6px 8px"
  compose-card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    padding: "14px"
  embed-card:
    backgroundColor: "{colors.hover-fill}"
    rounded: "{rounded.md}"
    padding: "10px"
  dm-bubble-mine-bluesky:
    backgroundColor: "{colors.bluesky-blue}"
    textColor: "#FFFFFF"
    rounded: "{rounded.bubble}"
    padding: "7px 11px"
  dm-bubble-theirs:
    backgroundColor: "rgba(0, 0, 0, 0.09)"
    textColor: "{colors.label-primary}"
    rounded: "{rounded.bubble}"
    padding: "7px 11px"
  unread-badge:
    backgroundColor: "{colors.danger-red}"
    textColor: "#FFFFFF"
    rounded: "{rounded.full}"
    height: "16px"
---

# Design System: CrossPost

## Overview

**Creative North Star: "The Quiet Switchboard"**

CrossPost is one desk wired to two networks. The window is three columns (composer, Mastodon, Bluesky) and the posts are the content; the app itself is system chrome and stays out of their way. Color does one job: it tells you which network a thing belongs to, or which action you took. Everything else is neutral system surface, hairline dividers, and secondary-label gray.

The system is restrained, dense but calm, Mac-native, and readable first. Many posts fit on screen at once, separated by hairlines rather than boxes. Post text is the largest type in a column, and names, handles, timestamps, and chrome step down behind it. Where AppKit or SwiftUI already has an answer (toolbar, `.bar` material, menus, segmented pickers, sheets, SF Symbols, system font, light and dark appearances), CrossPost uses it unchanged.

The two networks behave differently, and the interface says so. Anything that exists on only one network looks like it exists on only one network.

The system rejects four things: timeline posts as bordered floating cards, web-app chrome, flooding headers or backgrounds with brand color, and visual parity that fakes behavior the networks don't share.

**Key Characteristics:**
- Edge-to-edge timeline rows divided by hairlines; hover is a 4% fill, never a border.
- Network color appears only as small marks: the header glyph, active states, links, mentions, the network's own prominent buttons, and your own DM bubbles.
- System typography (SF Pro). Body text runs 14–18px and scales with the Reading text size setting; meta text is 12.5px in secondary gray.
- Flat at rest. Depth comes from system materials, and shadows appear only on transient overlays.
- Native controls, native shortcuts, native light and dark appearances; nothing is hand-inverted.

## Colors

A neutral system canvas with two network accents and a small set of semantic action colors, each used sparingly.

### Primary
- **Mastodon Blurple** (`mastodon-blurple`): Mastodon's brand color. Marks the Mastodon column's identity glyph, its links, mentions, and hashtags, its active header states, its own prominent buttons (Follow, Open Settings), the visibility menu, selected-target pill tint, and your own Mastodon DM bubbles.
- **Bluesky Blue** (`bluesky-blue`): Bluesky's brand color, used in exactly the same roles in the Bluesky column.
- **System Accent** (`system-accent`): the user's macOS accent color. Used only where an action spans both networks or neither: the composer's Post button, the composer drop target, and mention-suggestion selection.

### Secondary
- **Like Pink** (`like-pink`): the engaged state of Like everywhere it appears (system pink).
- **Repost Green** (`repost-green`): the engaged state of Repost/Boost everywhere (system green); also the "sent" confirmation in sheets.

### Tertiary
- **Danger Red** (`danger-red`): validation failures, over-limit character counts, send errors, the unread badge, and destructive menu items (system red).
- **Warning Orange** (`warning-orange`): character counts near the limit and the transient action-error glyph (system orange).

### Neutral
All neutrals are AppKit semantic colors (`textBackgroundColor`, `windowBackgroundColor`, `.primary`/`.secondary` labels, `Color.primary` at fixed opacities). The frontmatter records their light-appearance values; dark values come from the system, never from manual inversion.
- **Surface** (`surface`): window and text backgrounds. On current macOS both render white in light appearance.
- **Primary Label** (`label-primary`): names, post bodies, titles.
- **Secondary Label** (`label-secondary`): handles, timestamps, counts at rest, context lines, header icons, empty-state text. The most-used foreground in the app.
- **Hairline** (`hairline`): card strokes, pill strokes, and toast outlines.
- **Hover Fill** (`hover-fill`): row hover, unselected pill fill, link-card background.
- **Placeholder Fill** (`placeholder-fill`): avatar and skeleton placeholders.
- **Avatar Ring** (`avatar-ring`): the 0.5px ring around avatars.

**The Network Ownership Rule.** A network's accent appears only inside that network's column or on controls scoped to that network. The composer, which posts to both, uses the system accent.

**The Small Marks Rule.** Brand color is never a background or header fill. It colors glyphs, text, 10% tints, and 30% strokes. A screen with a solid block of blurple or blue is wrong.

**The Action Color Rule.** Pink means liked, green means reposted, in every row type. At rest, action icons are secondary gray.

## Typography

**Display Font:** none. CrossPost has no display tier.
**Body Font:** SF Pro (system font via `Font.system`), falling back to `-apple-system, system-ui` in web renderings.
**Label/Mono Font:** SF Pro with tabular figures (`monospacedDigit`) for counts.

**Character:** one family at a tight, close-stepped scale. Hierarchy comes from weight (semibold names and titles) and the secondary label color, not from size jumps.

### Hierarchy
- **Column Title** (600, 15px): the network name in column headers ("Mastodon", "Bluesky"), "New Post", sheet titles.
- **Column Subtitle** (500, 12px, secondary): the feed menu ("Home ⌄") or pushed route title ("Thread", a profile name) under a column's network name.
- **Name Large** (600, 16px): author name in the expanded post detail.
- **Name** (600, 14px timeline / 14.5px sheets): author display names.
- **Body** (400, 14px timeline, 15px sheets and composer, 18px expanded detail, as `Theme.timelineContentSize`, `contentSize`, and `expandedContentSize`; system leading plus 3px line spacing): post text. Adds +0/+2/+4px for the Standard/Larger/Largest Reading text size setting, which also applies to quotes, bios, and DMs.
- **Meta** (400, 12.5px, secondary): handles and relative timestamps in timeline rows (handles are 13px in sheets). Timestamps are compact and locale-aware: "now", "5m", "13h", "3d", then a short date ("Oct 12", with the year outside the current year). The tooltip gives the full date and time; VoiceOver reads the full phrase ("13 hours ago").
- **Context** (500, 12px, secondary or accent): "boosted"/"reposted" lines and "In reply to".
- **Count** (400, 12.5px, tabular): engagement counts, compact notation (1.2K).
- **Label** (500, 11px): link-card provider, section headers ("People", "Pinned", at 600).

**The Content Leads Rule.** In a timeline row, post body text is the largest type and the only type in full primary contrast at regular weight. Chrome never outsizes content.

**The Reading Size Rule.** Anything a person reads (post bodies, quotes, bios, DMs) goes through `readingFont` so the Reading text size setting reaches it. Metadata and chrome stay fixed.

## Layout

A three-column `HSplitView`: the composer (330–440px, ideal 370, hideable with ⇧⌘C) and two feed columns that always share the remaining width equally (580px minimum combined, about 290px each). The window minimum is 920 × 560 with the composer shown and 600 × 560 without it.

Every column opens with a 52px header on the `.bar` material with a hairline divider below: the network glyph and name in the column title style, stacked above the feed menu in the column subtitle style, then trailing 28 × 28 icon buttons. In-column navigation (threads, profiles, search) pushes a back-chevron header of the same height that keeps the network name on top and shows the route title beneath it.

Timeline rows run edge to edge with 14px horizontal and 10px vertical padding. The avatar (40px) sits 10px from content, rows stack their parts 6px apart, and action buttons sit 20px apart with share and overflow pushed trailing. List rows (search, followers) use 16 × 12 padding with 42px avatars; sheet and detail contexts use 44px avatars, and the expanded detail uses 54px. Sheets are 420px wide with 20px padding. The composer scroll area pads 14px and stacks thread cards 12px apart.

Spacing sits on a loose 8pt grid with deliberate 2px offsets (6, 10, 14). Use the named Theme metrics, not new literals.

## Elevation & Depth

Flat at rest. Hierarchy comes from subtle fills (4–6% primary), 0.75px hairlines, and the system `.bar` material on column headers. Nothing in the timeline casts a shadow.

### Shadow Vocabulary
- **Toast** (`0 3px 10px rgba(0,0,0,0.18)` on `.regularMaterial`): the transient action-error capsule that floats over a feed.
- **Lightbox image** (`0 0 30px rgba(0,0,0,0.4)`): the full-window image viewer over its dimmed backdrop.

**The Flat-At-Rest Rule.** Shadows belong only to transient overlays that sit above the window's content plane. If a persistent surface needs separation, use a hairline or the `.bar` material.

## Shapes

All rounded rectangles use the continuous (squircle) corner style. Avatars are circles with a 0.5px ring. Media and embeds clip to 10px corners, composer cards to 12px, small editors and suggestion lists to 6–8px, skeleton bars to 4px, and DM bubbles to 15px. Toggles and notices that aren't rows use capsules: target pills, the unread badge, the error toast. Quoted posts carry a 3px capsule rule on the leading edge in the network accent at 55% opacity.

## Components

### Buttons
Native button styles throughout; CrossPost does not draw its own button chrome.
- **Shape:** system bezels (`.borderedProminent`, `.bordered`, `.borderless`) at system radii.
- **Primary:** `.borderedProminent`. The composer's full-width Post button is `.large` in the system accent with ⌘↩. Network-scoped primaries (Follow, Open Settings) are tinted with that network's accent.
- **Hover / Focus:** system-provided; focus rings are the system's.
- **Secondary / Ghost:** `.bordered` `.small` for secondary profile actions and Try Again; `.borderless` for header icons and "Add post to thread".
- **Post actions:** plain SF Symbol buttons (13.5px) in secondary gray with a 28 × 28 hit area and an optional compact count. Engaged Like and Repost take pink and green and fire a trackpad haptic tick.

### Chips
- **Style:** the composer's target pills. A capsule with 8 × 6 padding, a 12px symbol, and 12px medium text. Selected: network accent at 10% fill and 30% stroke with `checkmark.circle.fill`. Unselected: hover fill with hairline stroke and an empty circle. Locked: `lock.circle`.
- **State:** a 0.15s snappy transition between states, removed under Reduce Motion.

### Cards / Containers
- **Corner Style:** 12px continuous for composer cards and the compose footer; 10px for link and quote embeds.
- **Background:** text background for composer cards; 3.5–4% primary fill for embeds.
- **Shadow Strategy:** none (see Elevation & Depth).
- **Border:** 0.75px hairline for composer cards; 8% primary stroke for embeds.
- **Internal Padding:** 14px for composer post cards, 12px for the footer, 10px for embeds.

### Inputs / Fields
- **Style:** the composer editor sits borderless inside its card with a 15px secondary placeholder ("What's on your mind?"). Sheet editors use an 8px-radius text-background field with 8px padding and a quaternary stroke.
- **Focus:** system focus behavior.
- **Error / Disabled:** the character counter goes from secondary to orange near the limit and red over it. Validation messages are red caption text that names the post and network.

### Navigation
- **Column header:** the network glyph (in the network accent) and name lead, so the two columns read apart at a glance. Beneath it, the current feed is a plain-styled menu with a small chevron (Home / Notifications / Messages, with a checkmark on the current feed). Trailing icons are a bell (filled and accent-colored when active, with the red unread badge), search, and an overflow menu. Header icons are 13px medium in secondary gray with 28 × 28 targets.
- **Window toolbar:** native unified toolbar with a leading sidebar toggle for the composer and trailing Refresh All (⌘R) and Settings.
- **Keyboard:** each feed list (Home, thread, profile, saved posts) takes keyboard focus as a whole, and one post in it is focused, anchored by post id so a refresh doesn't move it. ↑/↓ and J/K move the focus, Space and ⇧Space page, Return opens the thread, Esc pops the route, R/L/B reply, like, and repost through the action bar's own paths, and ←/→ move the keyboard between the two feeds. A focused post that isn't wholly visible scrolls to the top of the column (jumping under Reduce Motion), and VoiceOver focus follows it. File › New Post (⌘N) focuses the composer; Esc in the composer returns to the last feed. The Post menu lists every key in its item titles instead of as key equivalents, because AppKit matches bare-key menu equivalents before a text view sees the key. No key deletes.
- **Composer header:** "New Post" title, a small segmented Edit / Mastodon / Bluesky preview picker, and a "…" menu holding New Draft… (the same overflow style as the feed headers, so the header fits the 330pt minimum).

### Timeline Row (signature)
The core of the app. Content runs top to bottom: an optional context line (boost attribution, then a tappable accent "In reply to"), the avatar + name + handle header with the visibility glyph and relative timestamp trailing, the selectable body, media at 10px corners, then the link card, the quoted post, and the action bar. Hover adds the 4% fill over 0.12s. A plain click opens the thread; dragging selects text. A Mastodon content warning stands in for the body, media, link card, and quote as a 4%-fill row with the warning in the reading font and a "Show post" toggle in the network accent. Sensitive media is blurred under a material "Sensitive content" label until clicked, independently of the warning. A 50%-opacity divider sits at the bottom edge. The keyboard-focused post draws the system focus ring (`Theme.focusRing`, the system keyboard focus indicator color: a 3px stroke on a 6px continuous corner, inset 2px so the column edges never clip it) over the row. It replaces neither the hover fill nor the divider, and it shows only while that list has keyboard focus. Loading shows static skeleton rows with a fixed sheen, never a perpetual animation.

### Recent Posts
The composer's idle state: a `sectionHeader` "Recent Posts" over one composer card of rows split by inset hairlines. Each row shows the post's first text (reading font, 14px, two lines), a meta line (`Thread · N posts ·` and the relative time), and one group per network: the network glyph in its accent, then reply, repost, and like counts in secondary gray. A group is a plain button with a hover fill that opens that copy's thread in its own column. Groups with nothing to open show secondary text instead: "Deleted", "Older than your recent posts", "Just posted", or "—" with the error as a tooltip. Loading shows a static skeleton bar per group. Networks without an account are omitted. The section fades out when the user starts writing (no animation under Reduce Motion).

### Unread Badge
The system red capsule: 10px bold white tabular digits, 16px minimum, circular for one digit, capped at "99+". The dock badge mirrors the combined unread count from both networks.

### Message Bubble
Your own messages fill with the network accent and white text; theirs fill with secondary gray at 18%. Both use a 15px continuous corner, 7 × 11 padding, and a 260px maximum width, with an 11px secondary time below.

## Do's and Don'ts

### Do:
- **Do** use the `Theme` tokens (fonts, metrics, `hairline`, `hoverFill`, `likeTint`, `repostTint`) instead of new literals.
- **Do** keep timeline rows edge to edge with a hairline divider and a 4% hover fill.
- **Do** use the network accent only inside its own column or on controls scoped to that network; use the system accent for cross-network actions.
- **Do** route readable text through `readingFont` so the Reading text size setting applies.
- **Do** use native controls, materials, SF Symbols, and AppKit semantic colors, and check every change in both light and dark appearances.
- **Do** show network differences visibly: Bluesky's audience is a fixed "Public" label, not a menu; Edit and Pin appear only on Mastodon posts.
- **Do** honor Reduce Motion for every transition and keep loading states static.

### Don't:
- **Don't** render timeline posts as bordered floating cards.
- **Don't** use web-app chrome: custom headers, hamburger menus, or hand-drawn controls where AppKit has a native one.
- **Don't** flood headers, backgrounds, or large surfaces with Mastodon purple or Bluesky blue.
- **Don't** fake parity between the networks with identical treatments for features that behave differently.
- **Don't** add shadows to persistent surfaces; shadows are for transient overlays only.
- **Don't** let chrome or metadata type outsize post body text.
