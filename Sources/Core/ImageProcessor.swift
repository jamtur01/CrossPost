import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessor {
    enum ProcessingError: Error, CustomStringConvertible, LocalizedError {
        case decodeFailed
        case encodeFailed
        case cannotFitBudget(bytes: Int, budget: Int)
        var description: String {
            switch self {
            case .decodeFailed: return "Could not read image data"
            case .encodeFailed: return "Could not encode image data"
            case .cannotFitBudget(let b, let budget):
                return "Image is \(b) bytes; could not compress under \(budget) bytes"
            }
        }
        var errorDescription: String? { description }
    }

    /// Whether `data` is a decodable image. Used to reject a corrupt attachment
    /// up front, before any post in a thread is published. Uses the same ImageIO
    /// pipeline as `jpegUnderBudget`, so passing here means the encode can't fail
    /// on the same bytes later, mid-thread.
    static func canDecode(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    /// Qualities tried at each scale step, best first. The ladder stops at 0.4:
    /// below that JPEG artifacts are visible on photos while the size win is
    /// small, so past it we downscale instead.
    static let qualityLadder: [Double] = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4]

    /// Re-encode `data` as JPEG no larger than `maxBytes`, scaling down if needed.
    /// `maxBytes` defaults to Bluesky's per-image limit; Mastodon passes its own.
    /// EXIF orientation is baked into the pixels (portrait photos upload upright)
    /// and no other metadata — EXIF, GPS, maker notes — survives into the output.
    static func jpegUnderBudget(_ data: Data,
                                maxBytes: Int = TargetLimits.blueskyImageBytes) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ProcessingError.decodeFailed }

        var maxPixel = max(width, height)
        var lastOversize = 0
        // Shrink until a quality pass fits the budget. The factor and iteration
        // count drive any realistic source well under the budget before the loop
        // ends (0.75^16 ≈ 0.01), so an image can't fail mid-thread and strand
        // already-published posts. Each scale step decodes and rasterises the
        // source once; only the JPEG quality varies inside it.
        for _ in 0..<16 where maxPixel > 0 {
            guard let bitmap = uprightBitmap(from: source, maxPixel: maxPixel) else {
                throw ProcessingError.decodeFailed
            }
            for quality in qualityLadder {
                guard let encoded = encodeJPEG(bitmap, quality: quality) else {
                    throw ProcessingError.encodeFailed
                }
                if encoded.count <= maxBytes { return encoded }
                lastOversize = encoded.count
            }
            maxPixel = Int(Double(maxPixel) * 0.75)
        }
        // Unreachable for real images; surface a clear error rather than posting oversized.
        throw ProcessingError.cannotFitBudget(bytes: lastOversize, budget: maxBytes)
    }

    /// Decode one scale step: ImageIO applies the EXIF orientation transform
    /// while scaling, then any transparency is flattened onto white — JPEG has
    /// no alpha channel, and letting the encoder drop it would render
    /// transparent regions black.
    private static func uprightBitmap(from source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return flattenedOntoWhite(image)
    }

    private static func flattenedOntoWhite(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        return context.makeImage()
    }

    /// Encode via CGImageDestination passing only the compression quality, so no
    /// source metadata is copied into the upload.
    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
