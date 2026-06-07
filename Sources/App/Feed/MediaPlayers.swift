import SwiftUI
import AVKit
import AppKit

/// Autoplaying, muted, looping player for MP4/HLS clips — Mastodon `gifv` and
/// video, and Bluesky video. Mirrors how native clients play motion media inline.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> LoopingPlayerNSView {
        LoopingPlayerNSView(url: url, gravity: gravity)
    }

    func updateNSView(_ nsView: LoopingPlayerNSView, context: Context) {}

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
        player.play()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
/// can't decode GIFs, but NSImageView animates them natively.
struct AnimatedGIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        context.coordinator.load(url, into: view)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var task: URLSessionDataTask?

        func load(_ url: URL, into view: NSImageView) {
            task?.cancel()
            task = URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { view.image = image }
            }
            task?.resume()
        }
    }
}
