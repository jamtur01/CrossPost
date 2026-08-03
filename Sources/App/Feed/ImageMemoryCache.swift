import AppKit
import Foundation

final class CachedImageEntry {
    let image: NSImage
    let cost: Int

    init(image: NSImage, cost: Int) {
        self.image = image
        self.cost = cost
    }
}

private final class ImageRequestKey: NSObject {
    let request: ImageRequest

    init(_ request: ImageRequest) {
        self.request = request
    }

    override var hash: Int {
        request.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImageRequestKey else { return false }
        return request == other.request
    }
}

final class ImageMemoryCache: @unchecked Sendable {
    private let staticImages = NSCache<ImageRequestKey, CachedImageEntry>()
    private let animatedImages = NSCache<ImageRequestKey, CachedImageEntry>()

    init() {
        staticImages.countLimit = 300
        staticImages.totalCostLimit = 192 * 1024 * 1024
        animatedImages.countLimit = 24
        animatedImages.totalCostLimit = 128 * 1024 * 1024
    }

    func entry(for request: ImageRequest) -> CachedImageEntry? {
        cache(for: request).object(forKey: ImageRequestKey(request))
    }

    func insert(_ entry: CachedImageEntry, for request: ImageRequest) {
        cache(for: request).setObject(
            entry,
            forKey: ImageRequestKey(request),
            cost: entry.cost
        )
    }

    private func cache(
        for request: ImageRequest
    ) -> NSCache<ImageRequestKey, CachedImageEntry> {
        request.representation == .animated ? animatedImages : staticImages
    }
}
