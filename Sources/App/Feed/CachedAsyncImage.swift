import SwiftUI
import AppKit

/// Process-wide cache of decoded static images (avatars, post media, link-card
/// thumbs). `AsyncImage` keeps no cache of its own beyond URLCache, so lazy feed
/// scrolling re-fetches and re-decodes every avatar as rows recycle; keeping the
/// decoded `NSImage` here makes re-appearing rows render instantly. Animated GIFs
/// keep their own cache in `AnimatedGIFView` (they need whole-file `NSImage` data
/// for frame animation and a tighter budget).
enum ImageCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()
}

/// Drop-in replacement for `AsyncImage` backed by `ImageCache`: a cached URL
/// renders synchronously on the first body evaluation (no placeholder flash),
/// a miss downloads once and populates the cache for every other view showing
/// that URL.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        _phase = State(initialValue: Self.cachedPhase(for: url) ?? .empty)
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private static func cachedPhase(for url: URL?) -> AsyncImagePhase? {
        guard let url, let hit = ImageCache.shared.object(forKey: url as NSURL) else { return nil }
        return .success(Image(nsImage: hit))
    }

    private func load() async {
        if let cached = Self.cachedPhase(for: url) {
            phase = cached
            return
        }
        guard let url else {
            phase = .empty
            return
        }
        // A recycled view whose URL changed must not keep showing the old image.
        if case .success = phase { phase = .empty }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = NSImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            ImageCache.shared.setObject(decoded, forKey: url as NSURL, cost: data.count)
            guard !Task.isCancelled else { return }
            phase = .success(Image(nsImage: decoded))
        } catch {
            // Cancellation means the view disappeared or the URL changed; leave
            // the placeholder rather than flashing a failure state.
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }
}

extension CachedAsyncImage {
    /// The `AsyncImage(url:content:placeholder:)` shape used across the app.
    init<I: View, P: View>(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }
}
