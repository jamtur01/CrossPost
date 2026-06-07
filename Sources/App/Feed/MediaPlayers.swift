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

    init(url: URL, gravity: AVLayerVideoGravity) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = gravity
        playerLayer.player = player
        layer?.addSublayer(playerLayer)

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        // Seek-to-zero on end loops both file-based (MP4) and HLS items reliably.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setActive(_ active: Bool) {
        if active { player.play() } else { player.pause() }
    }

    func stop() {
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    deinit { stop() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
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

        func load(_ url: URL, into view: NSImageView) {
            if let cached = Self.cache.object(forKey: url as NSURL) {
                view.image = cached
                return
            }
            task?.cancel()
            task = URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, data.count <= Self.maxBytes,
                      let image = NSImage(data: data) else { return }
                Self.cache.setObject(image, forKey: url as NSURL, cost: data.count)
                DispatchQueue.main.async { view.image = image }
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
