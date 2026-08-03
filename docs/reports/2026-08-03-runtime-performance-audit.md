# CrossPost Runtime Performance Audit

**Date:** 2026-08-03  
**Audited revision:** `a25471e`  
**Build:** CrossPost 0.4.19, Release configuration  
**Platform:** macOS 26.5.2, Apple silicon

## Executive summary

The previous 47–58% idle CPU regression is fixed. The rebuilt Release app no longer shows
sustained CPU load on populated Home feeds, minimized or hidden windows, or row-light routes.

One reproducible performance defect remains: the shared relative-timestamp clock wakes and
relayouts more of the window than necessary once per minute, including while CrossPost is
inactive. Several additional conditional risks were identified from source inspection, but they
were not active in the sampled Home viewport and are not claimed as live regressions.

## Method

The audit used the built Release application, populated live feeds, and the following tools:

- `top` for repeated process CPU, memory, thread, and power samples;
- `sample` for main-thread and worker-thread stack attribution;
- `vmmap` for physical-footprint and region accounting;
- `nettop` for process network deltas;
- unified logs for stream reconnect behavior;
- process-targeted macOS automation for route, minimized, hidden, and restored states;
- source inspection of feed lifecycle, image loading, media playback, polling, and publication.

The profiled application was stopped after measurement.

## Runtime results

| Scenario | Duration | Median CPU | Mean CPU | p95 | Max |
|---|---:|---:|---:|---:|---:|
| Populated Home, explicitly activated | 90s | 0.1% | 0.136% | 0.3% | 2.4% |
| Populated Home, minimized | 60s | 0.1% | 0.13% | 0.1% | 1.8% |
| Populated Home, hidden | 60s | 0.1% | 0.15% | 0.1% | 2.8% |
| Mixed row-light routes | 60s | 0.0% | 0.223% | 1.3% | 2.8% |
| Restored Home, inactive | 30s | 0.0% | 0.033% | 0.0% | 0.5% |
| Stationary inactive Home | 120s | 0.0% | 0.29% | 0.0% | 9.2% |

The stationary inactive run contained two isolated spikes, 8.2% and 9.2%, roughly one minute
apart. It did not show continuous load.

A 112.8-second process sample recorded 260 process-wide on-CPU samples. The main thread
accounted for 239 samples; 18 background threads were idle or negligible.

## Findings

### Medium: Timestamp clock invalidates the root window while inactive

`Sources/App/Feed/MainView.swift:11,33,41,64-78` changes a root-level environment value every
minute. Timestamp rows consume it at `Sources/App/Feed/Components.swift:229-236`.

The live sample captured:

- `MainView.runRelativeTimestampClock()`;
- `RelativeTimestampView.body`;
- AttributeGraph updates;
- lazy-stack measurement and layout;
- AppKit popup-menu and accessibility reconstruction;
- Core Animation commits.

The clock is not responsible for the former sustained 50% regression, but it causes the remaining
periodic spikes. Its current placement applies the changing environment above the composer, both
feeds, toolbar, lightbox, and menus.

Recommended correction:

1. Suspend minute updates while the application or window is inactive, hidden, minimized, or
   occluded.
2. Refresh immediately when presentation becomes active again.
3. Scope `relativeTimestampNow` to feed content rather than the entire `HSplitView` and toolbar.
4. Keep one shared clock; do not return to per-row timers.

### Medium, conditional: Notification polling can repeat substantial unchanged work

A Bluesky notifications refresh can perform:

- up to two notification-page requests;
- up to four concurrent post-hydration requests;
- up to four sequential relationship batches;
- one `updateSeen` write.

Relevant paths:

- `Sources/App/Feed/FeedPanelModel+Loading.swift:126-151`;
- `Sources/App/Feed/FeedPanelModel+Actions.swift:51-91`;
- `Sources/Core/Feed/BlueskyFeedService.swift:41-50,88-99,101-117,434-448`.

This can repeat every 30 seconds while Notifications is selected and the application is active,
even when the visible snapshot is unchanged. Cache hydrated posts and relationship states, and
avoid `updateSeen` when no new notification needs acknowledgement.

### Medium, conditional: Immediately ending Mastodon streams reconnect every two seconds

`Sources/App/Feed/FeedPanelModel+Lifecycle.swift:18-44` resets reconnect backoff to two seconds as
soon as it obtains a stream, before the stream has demonstrated that it is healthy. A server that
repeatedly accepts and immediately closes the stream can therefore reconnect indefinitely at a
two-second cadence.

The profiled live session did not exhibit this behavior: 15 minutes of logs contained no reconnect
loop. Reset the backoff only after receiving the first event or maintaining the connection for a
minimum healthy duration.

### Medium, conditional burst: Distinct image requests have no global concurrency budget

`CachedAsyncImage` coalesces duplicate requests and bounds every individual response and decode,
but distinct URLs can create unbounded concurrent source and detached decode tasks during
cold-cache fast scrolling.

The sampled feed showed no sustained impact. A loader-wide request and decode limit would bound
worst-case network traffic, memory, and utility-thread contention.

### Medium, conditional: Motion players have no global concurrency budget

Every visible GIF or video tile can own and run its own animated image or `AVPlayerItem`.
Visibility gating and teardown are strong, but a viewport containing multiple motion tiles can
decode all of them concurrently.

A global active-motion budget would protect battery life and responsiveness in media-heavy
feeds.

### Medium, one-shot: Attachment validation fully decodes original images

`Sources/App/Feed/AttachmentPicker.swift:166-186,217-228,275-289` buffers the entire source.
`Sources/Core/ImageProcessor.swift:16-19` raster-decodes the full original during validation before
the later thumbnail downsample. Very large TIFF, PNG, HEIC, or JPEG files can therefore cause a
transient memory and CPU spike.

Add file-byte and source-pixel limits, and validate image metadata without fully rasterizing the
source.

## Memory and network

- Row-light route footprint: approximately 70 MiB.
- Restored populated Home footprint: 115.4 MiB.
- Footprint after another eight minutes: 112.0 MiB.
- Peak footprint during navigation and image loading: 135.5 MiB.
- No monotonic memory growth was observed.
- Inactive network traffic over 120 seconds: 96 bytes received and 200 bytes sent across four
  changed intervals.
- Existing image caches are decoded-cost bounded: 192 MiB for static images and 128 MiB for
  animated images.
- Route changes released enough image and view state to reduce the process footprint materially.

## Verified non-issues

- No remaining `Shimmer`, `repeatForever`, `TimelineView`, display link, or per-row timer.
- Static loading placeholders do not continuously animate.
- Feed rows are mounted lazily.
- Polling and live-event bursts are active-plus-one-trailing coalesced.
- Mastodon suppresses feed polling while its live stream is connected.
- Polling is gated while the application is inactive.
- Static images are bounded and downsampled off the main thread.
- Duplicate image requests coalesce, and cancellation tears down orphaned work.
- Video and GIF resources unload when offscreen, inactive, minimized, occluded, or dismantled.
- Search, profile, conversation, and navigation tasks have cancellation and generation fencing.

## Recommended order

1. Gate and narrow the shared relative-timestamp clock.
2. Reduce unchanged Notifications hydration, relationship, and `updateSeen` work.
3. Preserve Mastodon reconnect backoff until a connection proves healthy.
4. Add global image-decode and motion-player budgets if media-heavy profiling shows contention.
5. Bound attachment source size and pixel count before full decode.
