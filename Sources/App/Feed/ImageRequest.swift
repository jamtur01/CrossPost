import CoreGraphics
import Foundation

enum ImageRepresentation: Hashable, Sendable {
    case avatar
    case thumbnail
    case timeline
    case original
    case animated

    private struct Limits {
        let downloadBytes: Int
        let targetDimension: Int
        let sourcePixels: Int
        let decodedBytes: Int
        let defaultSide: CGFloat
    }

    var maxDownloadBytes: Int {
        limits.downloadBytes
    }

    var maxTargetDimension: Int {
        limits.targetDimension
    }

    var maxSourcePixelCount: Int {
        limits.sourcePixels
    }

    var maxDecodedBytes: Int {
        limits.decodedBytes
    }

    var defaultTargetSize: CGSize {
        CGSize(width: limits.defaultSide, height: limits.defaultSide)
    }

    private var limits: Limits {
        switch self {
        case .avatar:
            Limits(downloadBytes: 5 << 20, targetDimension: 512,
                   sourcePixels: 40_000_000, decodedBytes: 2 << 20, defaultSide: 256)
        case .thumbnail:
            Limits(downloadBytes: 10 << 20, targetDimension: 1200,
                   sourcePixels: 60_000_000, decodedBytes: 8 << 20, defaultSide: 1024)
        case .timeline:
            Limits(downloadBytes: 24 << 20, targetDimension: 2400,
                   sourcePixels: 100_000_000, decodedBytes: 24 << 20, defaultSide: 2048)
        case .original:
            Limits(downloadBytes: 64 << 20, targetDimension: 4096,
                   sourcePixels: 160_000_000, decodedBytes: 72 << 20, defaultSide: 4096)
        case .animated:
            Limits(downloadBytes: 32 << 20, targetDimension: 2400,
                   sourcePixels: 24_000_000, decodedBytes: 128 << 20, defaultSide: 1600)
        }
    }
}

struct ImageRequest: Hashable, Sendable {
    struct PixelSize: Hashable, Sendable {
        let width: Int
        let height: Int

        var maximumDimension: Int {
            max(width, height)
        }
    }

    let url: URL
    let representation: ImageRepresentation
    let targetSize: PixelSize

    init(
        url: URL,
        representation: ImageRepresentation = .thumbnail,
        targetSize: CGSize? = nil
    ) {
        let requestedSize = targetSize ?? representation.defaultTargetSize
        let maximum = representation.maxTargetDimension
        self.url = url
        self.representation = representation
        self.targetSize = PixelSize(
            width: Self.boundedDimension(requestedSize.width, maximum: maximum),
            height: Self.boundedDimension(requestedSize.height, maximum: maximum)
        )
    }

    private static func boundedDimension(_ value: CGFloat, maximum: Int) -> Int {
        guard value.isFinite, value > 0 else { return 1 }
        return max(1, Int(min(value, CGFloat(maximum)).rounded(.up)))
    }
}

enum ImageLoadingError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidStatus(Int)
    case invalidMIMEType(String?)
    case contentLengthExceeded(limit: Int, actual: Int64)
    case responseTooLarge(limit: Int)
    case invalidDimensions
    case pixelLimitExceeded(limit: Int)
    case decodedSizeExceeded(limit: Int)
    case decodeFailed
}
