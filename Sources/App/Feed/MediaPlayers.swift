import SwiftUI
import AVKit
import AppKit

/// Autoplaying, muted, looping player for MP4/HLS clips — Mastodon `gifv` and
/// video, and Bluesky video. Plays only while `isActive` (visible), to avoid
/// decoding offscreen rows in a lazy feed.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    var isActive: Bool = true

    func makeNSView(context: Context) -> LoopingPlayerNSView {
        LoopingPlayerNSView(url: url, gravity: gravity)
    }

    func updateNSView(_ nsView: LoopingPlayerNSView, context: Context) {
        // Lazy stacks recycle representables, so the same NSView can be handed a
        // different clip; without the URL update it would keep looping the old one.
        nsView.update(url: url)
        nsView.setActive(isActive)
    }

    static func dismantleNSView(_ nsView: LoopingPlayerNSView, coordinator: ()) {
        nsView.stop()
    }
}

final class LoopingPlayerNSView: NSView {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private var endObserver: NSObjectProtocol?
    private var url: URL
    // Creating an AVPlayerItem starts buffering immediately, so item creation is
    // deferred to the first activation (visibility) — a lazy list materialising
    // offscreen rows must not kick off video downloads.
    private var itemLoaded = false
    private var isActive = false

    init(url: URL, gravity: AVLayerVideoGravity) {
        self.url = url
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = gravity
        playerLayer.player = player
        player.isMuted = true
        player.actionAtItemEnd = .none
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(url newURL: URL) {
        guard newURL != url else { return }
        url = newURL
        // Nothing buffered yet: the next activation loads the new URL anyway.
        guard itemLoaded else { return }
        unloadItem()
        if isActive {
            loadItem()
            player.play()
        }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            if !itemLoaded { loadItem() }
            player.play()
        } else {
            player.pause()
        }
    }

    func stop() {
        isActive = false
        player.pause()
        unloadItem()
    }

    deinit { stop() }

    override func layout() {
        super.layout()
        // Core Animation implicit-animates layer frame changes by default, which
        // smears the video during window resizes and row relayouts.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    private func loadItem() {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        // Seek-to-zero on end loops both file-based (MP4) and HLS items reliably.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        itemLoaded = true
    }

    private func unloadItem() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
        itemLoaded = false
    }
}

/// Plays an animated GIF file (Bluesky Tenor/Giphy external embeds) — AVPlayer
/// can't decode GIFs, but NSImageView animates them natively. Decoded GIFs are
/// cached, in-flight downloads are cancelled on teardown, and animation pauses
/// when offscreen.
struct AnimatedGIFView: NSViewRepresentable {
    let url: URL
    var isActive: Bool = true

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = isActive
        context.coordinator.load(url, into: view)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        // Recycled by lazy stacks: reload when handed a different GIF's URL
        // (no-op when the URL is unchanged).
        context.coordinator.load(url, into: nsView)
        nsView.animates = isActive
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        // Animated GIFs keep every frame resident, so bound the cache and skip
        // absurdly large downloads — otherwise a feed of big Tenor/Giphy GIFs
        // (or a malicious external embed) can balloon memory unbounded.
        private static let maxBytes = 32 * 1024 * 1024
        private static let cache: NSCache<NSURL, NSImage> = {
            let cache = NSCache<NSURL, NSImage>()
            cache.countLimit = 40
            cache.totalCostLimit = 128 * 1024 * 1024
            return cache
        }()
        private var task: URLSessionDataTask?
        private var requestedURL: URL?

        func load(_ url: URL, into view: NSImageView) {
            guard url != requestedURL else { return }
            requestedURL = url
            if let cached = Self.cache.object(forKey: url as NSURL) {
                view.image = cached
                return
            }
            task?.cancel()
            // Don't keep animating the previous GIF while the new one downloads.
            view.image = nil
            task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, data.count <= Self.maxBytes,
                      let image = NSImage(data: data) else { return }
                Self.cache.setObject(image, forKey: url as NSURL, cost: data.count)
                DispatchQueue.main.async {
                    // A newer load superseded this one while it was in flight.
                    guard self?.requestedURL == url else { return }
                    view.image = image
                }
            }
            task?.resume()
        }

        func cancel() { task?.cancel() }
    }
}

/// Wraps a motion-media player (gif/video) with visibility tracking so it only
/// plays while onscreen, plus aspect-fit sizing and an optional corner badge.
struct MotionMedia<Player: View>: View {
    let media: FeedImage
    let fit: Bool
    let badge: String?
    @ViewBuilder let player: (Bool) -> Player

    @State private var visible = false

    var body: some View {
        Group {
            if fit {
                player(visible).aspectRatio(media.aspectRatio ?? 1.5, contentMode: .fit)
            } else {
                player(visible)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
        }
        .accessibilityLabel(media.altText.isEmpty ? "Animated media" : media.altText)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}
