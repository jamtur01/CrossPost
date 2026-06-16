import Foundation
import AppKit
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

    /// Re-encode `data` as JPEG no larger than `maxBytes`, scaling down if needed.
    /// `maxBytes` defaults to Bluesky's per-image limit; Mastodon passes its own.
    static func jpegUnderBudget(_ data: Data,
                                       maxBytes: Int = TargetLimits.blueskyImageBytes) throws -> Data {
        guard let image = NSImage(data: data) else { throw ProcessingError.decodeFailed }

        var scale = 1.0
        var lastEncoded: Data?
        // Shrink until a quality pass fits the budget. The factor and iteration
        // count drive any realistic source well under the budget before the loop
        // ends (0.75^16 ≈ 0.01), so an image can't fail mid-thread and strand
        // already-published posts.
        for _ in 0..<16 {
            for quality in stride(from: 0.9, through: 0.4, by: -0.1) {
                guard let encoded = encodeJPEG(image, scale: scale, quality: quality) else { continue }
                if encoded.count <= maxBytes { return encoded }
                lastEncoded = encoded
            }
            scale *= 0.75
        }
        // Unreachable for real images; surface a clear error rather than posting oversized.
        throw ProcessingError.cannotFitBudget(bytes: lastEncoded?.count ?? 0, budget: maxBytes)
    }

    private static func encodeJPEG(_ image: NSImage, scale: Double, quality: Double) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let targetWidth = Int(Double(bitmap.pixelsWide) * scale)
        let targetHeight = Int(Double(bitmap.pixelsHigh) * scale)
        guard targetWidth > 0, targetHeight > 0 else { return nil }

        let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: targetWidth, pixelsHigh: targetHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let resized else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        NSGraphicsContext.current?.imageInterpolation = .high
        bitmap.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        NSGraphicsContext.restoreGraphicsState()

        return resized.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
