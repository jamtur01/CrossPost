import Foundation
import AppKit
import UniformTypeIdentifiers

public enum ImageProcessor {
    public enum ProcessingError: Error, CustomStringConvertible, LocalizedError {
        case decodeFailed
        case encodeFailed
        case cannotFitBudget(bytes: Int, budget: Int)
        public var description: String {
            switch self {
            case .decodeFailed: return "Could not read image data"
            case .encodeFailed: return "Could not encode image data"
            case .cannotFitBudget(let b, let budget):
                return "Image is \(b) bytes; could not compress under \(budget) bytes"
            }
        }
        public var errorDescription: String? { description }
    }

    /// Re-encode `data` as JPEG without applying a small platform-specific byte budget.
    public static func jpegData(_ data: Data) throws -> Data {
        guard let image = NSImage(data: data) else { throw ProcessingError.decodeFailed }
        guard let encoded = encodeJPEG(image, scale: 1.0, quality: 0.9) else {
            throw ProcessingError.encodeFailed
        }
        return encoded
    }

    /// Re-encode `data` as JPEG no larger than `maxBytes`, scaling down if needed.
    /// Used for Bluesky's 1 MB per-image limit.
    public static func jpegUnderBudget(_ data: Data, maxBytes: Int = 1_000_000) throws -> Data {
        guard let image = NSImage(data: data) else { throw ProcessingError.decodeFailed }

        var scale = 1.0
        for _ in 0..<8 {
            for quality in stride(from: 0.9, through: 0.4, by: -0.1) {
                if let encoded = encodeJPEG(image, scale: scale, quality: quality),
                   encoded.count <= maxBytes {
                    return encoded
                }
            }
            scale *= 0.8
        }
        // Last attempt at the smallest scale/quality.
        if let encoded = encodeJPEG(image, scale: scale, quality: 0.4) {
            if encoded.count <= maxBytes { return encoded }
            throw ProcessingError.cannotFitBudget(bytes: encoded.count, budget: maxBytes)
        }
        throw ProcessingError.decodeFailed
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
        bitmap.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        NSGraphicsContext.restoreGraphicsState()

        return resized.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
