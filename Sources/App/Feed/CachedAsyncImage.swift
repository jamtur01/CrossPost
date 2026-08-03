import AppKit
import Foundation
import ImageIO
import SwiftUI

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

actor BoundedImageLoader {
    static let shared = BoundedImageLoader()

    private struct InFlight {
        var waiters: [UUID: CheckedContinuation<CachedImageEntry, Error>]
        let source: Task<Void, Never>
    }

    private nonisolated let cache: ImageMemoryCache
    private let dataClient: BoundedDataClient
    private var inFlight: [ImageRequest: InFlight] = [:]

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        cache = ImageMemoryCache()
        dataClient = BoundedDataClient(configuration: configuration)
    }

    nonisolated func cachedImage(for request: ImageRequest) -> NSImage? {
        cache.entry(for: request)?.image
    }

    nonisolated func cachedCost(for request: ImageRequest) -> Int? {
        cache.entry(for: request)?.cost
    }

    func image(for request: ImageRequest) async throws -> NSImage {
        try await entry(for: request).image
    }

    #if DEBUG
    func waiterCount(for request: ImageRequest) -> Int {
        inFlight[request]?.waiters.count ?? 0
    }
    #endif

    private func entry(for request: ImageRequest) async throws -> CachedImageEntry {
        if Task.isCancelled {
            throw CancellationError()
        }
        if let cached = cache.entry(for: request) {
            return cached
        }
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(
                    continuation: continuation,
                    waiterID: waiterID,
                    request: request
                )
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, for: request) }
        }
    }

    private func register(
        continuation: CheckedContinuation<CachedImageEntry, Error>,
        waiterID: UUID,
        request: ImageRequest
    ) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        if var current = inFlight[request] {
            current.waiters[waiterID] = continuation
            inFlight[request] = current
            return
        }
        let source = Task { [dataClient] in
            let result = await Self.load(request: request, dataClient: dataClient)
            complete(request: request, result: result)
        }
        inFlight[request] = InFlight(
            waiters: [waiterID: continuation],
            source: source
        )
    }

    private func cancelWaiter(_ waiterID: UUID, for request: ImageRequest) {
        guard var current = inFlight[request],
              let continuation = current.waiters.removeValue(forKey: waiterID) else { return }
        if current.waiters.isEmpty {
            inFlight[request] = nil
            current.source.cancel()
        } else {
            inFlight[request] = current
        }
        continuation.resume(throwing: CancellationError())
    }

    private func complete(
        request: ImageRequest,
        result: Result<CachedImageEntry, Error>
    ) {
        guard let current = inFlight.removeValue(forKey: request) else { return }
        if case let .success(entry) = result {
            cache.insert(entry, for: request)
        }
        for continuation in current.waiters.values {
            continuation.resume(with: result)
        }
    }

    private nonisolated static func load(
        request: ImageRequest,
        dataClient: BoundedDataClient
    ) async -> Result<CachedImageEntry, Error> {
        do {
            let data = try await dataClient.data(
                from: request.url,
                limit: request.representation.maxDownloadBytes
            )
            try Task.checkCancellation()
            let decodeTask = Task.detached(priority: .utility) {
                try Task.checkCancellation()
                return try decode(data: data, request: request)
            }
            let entry = try await withTaskCancellationHandler {
                try await decodeTask.value
            } onCancel: {
                decodeTask.cancel()
            }
            try Task.checkCancellation()
            return .success(entry)
        } catch {
            return .failure(error)
        }
    }

    private nonisolated static func decode(
        data: Data,
        request: ImageRequest
    ) throws -> CachedImageEntry {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageLoadingError.decodeFailed
        }
        let dimensions = try imageDimensions(source: source, request: request)
        if request.representation == .animated {
            return try decodeAnimated(
                data: data,
                source: source,
                dimensions: dimensions,
                request: request
            )
        }
        return try decodeStatic(source: source, request: request)
    }

    private nonisolated static func imageDimensions(
        source: CGImageSource,
        request: ImageRequest
    ) throws -> (width: Int, height: Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0,
            height > 0
        else {
            throw ImageLoadingError.invalidDimensions
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= request.representation.maxSourcePixelCount else {
            throw ImageLoadingError.pixelLimitExceeded(
                limit: request.representation.maxSourcePixelCount
            )
        }
        return (width, height)
    }

    private nonisolated static func decodeStatic(
        source: CGImageSource,
        request: ImageRequest
    ) throws -> CachedImageEntry {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: request.targetSize.maximumDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw ImageLoadingError.decodeFailed
        }
        let cost = cgImage.bytesPerRow * cgImage.height
        guard cost <= request.representation.maxDecodedBytes else {
            throw ImageLoadingError.decodedSizeExceeded(
                limit: request.representation.maxDecodedBytes
            )
        }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        return CachedImageEntry(image: image, cost: cost)
    }

    private nonisolated static func decodeAnimated(
        data: Data,
        source: CGImageSource,
        dimensions: (width: Int, height: Int),
        request: ImageRequest
    ) throws -> CachedImageEntry {
        let frameCount = max(1, CGImageSourceGetCount(source))
        let (rowBytes, rowOverflow) = dimensions.width.multipliedReportingOverflow(by: 4)
        let (frameBytes, frameOverflow) = rowBytes.multipliedReportingOverflow(
            by: dimensions.height
        )
        let (cost, costOverflow) = frameBytes.multipliedReportingOverflow(by: frameCount)
        guard !rowOverflow, !frameOverflow, !costOverflow,
              cost <= request.representation.maxDecodedBytes
        else {
            throw ImageLoadingError.decodedSizeExceeded(
                limit: request.representation.maxDecodedBytes
            )
        }
        guard let image = NSImage(data: data) else {
            throw ImageLoadingError.decodeFailed
        }
        return CachedImageEntry(image: image, cost: cost)
    }
}

enum CachedAsyncImagePhase {
    case unavailable
    case loading
    case success(Image)
    case failure(Error)

    var image: Image? {
        guard case let .success(image) = self else { return nil }
        return image
    }
}

struct CachedAsyncImage<Content: View>: View {
    private let request: ImageRequest?
    private let content: (CachedAsyncImagePhase) -> Content

    @State private var phase: CachedAsyncImagePhase
    @State private var phaseRequest: ImageRequest?

    init(
        url: URL?,
        representation: ImageRepresentation = .thumbnail,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (CachedAsyncImagePhase) -> Content
    ) {
        let request = url.map {
            ImageRequest(url: $0, representation: representation, targetSize: targetSize)
        }
        self.request = request
        self.content = content
        _phaseRequest = State(initialValue: request)
        if let request, let image = BoundedImageLoader.shared.cachedImage(for: request) {
            _phase = State(initialValue: .success(Image(nsImage: image)))
        } else {
            _phase = State(initialValue: request == nil ? .unavailable : .loading)
        }
    }

    var body: some View {
        content(displayPhase)
            .task(id: request) { await load() }
    }

    private var displayPhase: CachedAsyncImagePhase {
        guard phaseRequest == request else { return request == nil ? .unavailable : .loading }
        return phase
    }

    private func load() async {
        phaseRequest = request
        guard let request else {
            phase = .unavailable
            return
        }
        if let image = BoundedImageLoader.shared.cachedImage(for: request) {
            phase = .success(Image(nsImage: image))
            return
        }
        phase = .loading
        do {
            let image = try await BoundedImageLoader.shared.image(for: request)
            guard !Task.isCancelled else { return }
            phase = .success(Image(nsImage: image))
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }
}

extension CachedAsyncImage {
    init<I: View, P: View>(
        url: URL?,
        representation: ImageRepresentation = .thumbnail,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url, representation: representation, targetSize: targetSize) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }
}
