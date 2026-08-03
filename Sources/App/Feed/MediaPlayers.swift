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
        // Lazy stacks recycle representables, so URL and activity must update
        // atomically: an inactive recycled view must never load the new item.
        nsView.update(url: url, isActive: isActive)
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

    func update(url newURL: URL, isActive active: Bool) {
        if newURL != url {
            url = newURL
            unloadItem()
        }
        setActive(active)
    }

    private func setActive(_ active: Bool) {
        isActive = active
        guard active else {
            player.pause()
            unloadItem()
            return
        }
        if !itemLoaded { loadItem() }
        player.play()
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
        guard isActive, !itemLoaded else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        // Seek-to-zero on end loops both file-based (MP4) and HLS items reliably.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self, weak item] _ in
            guard let self, self.isActive, self.player.currentItem === item else { return }
            self.player.seek(to: .zero)
            self.player.play()
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
        context.coordinator.update(url: url, isActive: isActive, in: view)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        context.coordinator.update(url: url, isActive: isActive, in: nsView)
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: Coordinator) {
        nsView.animates = false
        nsView.image = nil
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
        private let requestLock = NSLock()
        private var requestGeneration = 0
        private var task: URLSessionDataTask?
        private var requestedURL: URL?
        private var loadedURL: URL?
        func update(url: URL, isActive: Bool, in view: NSImageView) {
            if url != requestedURL {
                cancelRequest()
                requestedURL = url
                loadedURL = nil
                view.image = nil
            }
            view.animates = isActive
            guard isActive else {
                cancelRequest()
                return
            }
            guard loadedURL != url else { return }
            if let cached = Self.cache.object(forKey: url as NSURL) {
                loadedURL = url
                view.image = cached
                return
            }
            guard task == nil else { return }
            startRequest(url: url, view: view)
        }
        func cancel() {
            cancelRequest()
            requestedURL = nil
            loadedURL = nil
        }
        deinit { task?.cancel() }
        private func startRequest(url: URL, view: NSImageView) {
            let generation = nextRequestGeneration()
            task = URLSession.shared.dataTask(with: url) { [weak self, weak view] data, _, _ in
                guard let self, self.isCurrentRequest(generation) else { return }
                let image = data.flatMap {
                    $0.count <= Self.maxBytes ? NSImage(data: $0) : nil
                }
                guard self.isCurrentRequest(generation) else { return }
                if let data, let image {
                    Self.cache.setObject(image, forKey: url as NSURL, cost: data.count)
                }
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, self.isCurrentRequest(generation),
                          self.requestedURL == url else { return }
                    self.task = nil
                    guard let image else { return }
                    self.loadedURL = url
                    view?.image = image
                }
            }
            task?.resume()
        }
        private func cancelRequest() {
            task?.cancel()
            task = nil
            invalidateRequests()
        }
        private func nextRequestGeneration() -> Int {
            requestLock.lock()
            defer { requestLock.unlock() }
            requestGeneration += 1
            return requestGeneration
        }
        private func invalidateRequests() {
            requestLock.lock()
            requestGeneration += 1
            requestLock.unlock()
        }
        private func isCurrentRequest(_ generation: Int) -> Bool {
            requestLock.lock()
            defer { requestLock.unlock() }
            return requestGeneration == generation
        }
    }
}

/// Wraps a motion-media player with row, window, and application visibility
/// tracking, plus aspect-fit sizing and an optional corner badge.
struct MotionMedia<Player: View>: View {
    let media: FeedImage
    let fit: Bool
    let badge: String?
    @ViewBuilder let player: (Bool) -> Player

    @State private var visibility = MotionVisibilityState.unavailable

    var body: some View {
        Group {
            if fit {
                player(visibility.allowsMotion)
                    .aspectRatio(media.aspectRatio ?? 1.5, contentMode: .fit)
            } else {
                player(visibility.allowsMotion)
            }
        }
        .background {
            MotionVisibilityObserver { visibility = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
}
