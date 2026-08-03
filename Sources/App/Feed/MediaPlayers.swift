import AppKit
import AVKit
import SwiftUI

/// Autoplaying, muted, looping player for MP4/HLS clips — Mastodon `gifv` and
/// video, and Bluesky video. Plays only while `isActive` (visible), to avoid
/// decoding offscreen rows in a lazy feed.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    var isActive: Bool = true

    func makeNSView(context _: Context) -> LoopingPlayerNSView {
        LoopingPlayerNSView(url: url, gravity: gravity)
    }

    func updateNSView(_ nsView: LoopingPlayerNSView, context _: Context) {
        // Lazy stacks recycle representables, so URL and activity must update
        // atomically: an inactive recycled view must never load the new item.
        nsView.update(url: url, isActive: isActive)
    }

    static func dismantleNSView(_ nsView: LoopingPlayerNSView, coordinator _: ()) {
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

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

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
        if !itemLoaded {
            loadItem()
        }
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
            guard let self, isActive, player.currentItem === item else { return }
            player.seek(to: .zero)
            player.play()
        }
        itemLoaded = true
    }

    private func unloadItem() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
        itemLoaded = false
    }
}

/// Plays GIF data through the bounded shared image loader. NSImageView performs
/// native frame animation, which pauses while the view is inactive.
struct AnimatedGIFView: View {
    private enum Phase {
        case idle
        case loading(URL)
        case success(URL, NSImage)
        case failure(URL)
    }

    private struct LoadIdentity: Hashable {
        let url: URL
        let isActive: Bool
    }

    let url: URL
    let previewURL: URL?
    let fit: Bool
    var isActive = true

    @State private var phase = Phase.idle

    var body: some View {
        content
            .task(id: LoadIdentity(url: url, isActive: isActive)) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case let .success(loadedURL, image) where loadedURL == url:
            AnimatedImageNSView(image: image, isActive: isActive)
        case let .loading(loadingURL) where loadingURL == url:
            Rectangle().fill(Color.primary.opacity(0.06)).loadingSheen()
        case let .failure(failedURL) where failedURL == url:
            preview
                .overlay { Image(systemName: "photo.badge.exclamationmark") }
        default:
            preview
        }
    }

    private func load() async {
        guard isActive else {
            phase = .idle
            return
        }
        let request = ImageRequest(
            url: url,
            representation: .animated,
            targetSize: CGSize(width: 1600, height: 1200)
        )
        if let image = BoundedImageLoader.shared.cachedImage(for: request) {
            phase = .success(url, image)
            return
        }
        phase = .loading(url)
        do {
            let image = try await BoundedImageLoader.shared.image(for: request)
            guard !Task.isCancelled else { return }
            phase = .success(url, image)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(url)
        }
    }

    private var preview: some View {
        CachedAsyncImage(
            url: previewURL,
            representation: .thumbnail,
            targetSize: CGSize(width: 1200, height: 1200)
        ) { image in
            if fit {
                image.resizable().scaledToFit()
            } else {
                image.resizable().scaledToFill()
            }
        } placeholder: {
            Rectangle().fill(Color.primary.opacity(0.06))
        }
    }
}

private struct AnimatedImageNSView: NSViewRepresentable {
    let image: NSImage
    let isActive: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context _: Context) {
        nsView.image = image
        nsView.animates = isActive
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator _: ()) {
        nsView.animates = false
        nsView.image = nil
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
