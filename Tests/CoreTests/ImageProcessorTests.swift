import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import CrossPost

final class ImageProcessorTests: XCTestCase {
    /// A solid-colour PNG built without `NSImage.lockFocus`, so it works headless.
    private func solidPNG(side: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testJpegUnderBudgetProducesJPEGMagicBytes() throws {
        let output = try ImageProcessor.jpegUnderBudget(solidPNG(side: 64), maxBytes: 10_000_000)
        XCTAssertFalse(output.isEmpty)
        XCTAssertEqual(Array(output.prefix(2)), [0xFF, 0xD8])   // JPEG SOI marker
    }

    func testJpegUnderBudgetStaysWithinBudget() throws {
        let output = try ImageProcessor.jpegUnderBudget(solidPNG(side: 512), maxBytes: 20_000)
        XCTAssertFalse(output.isEmpty)
        XCTAssertLessThanOrEqual(output.count, 20_000)
        XCTAssertEqual(Array(output.prefix(2)), [0xFF, 0xD8])
    }

    func testLargeImageScalesUnderBudgetWithoutThrowing() throws {
        // A large source must shrink to fit rather than fail (which mid-thread would
        // strand already-published posts).
        let output = try ImageProcessor.jpegUnderBudget(solidPNG(side: 3000),
                                                        maxBytes: TargetLimits.blueskyImageBytes)
        XCTAssertLessThanOrEqual(output.count, TargetLimits.blueskyImageBytes)
        XCTAssertEqual(Array(output.prefix(2)), [0xFF, 0xD8])
    }

    func testJpegUnderBudgetRejectsUndecodableInput() {
        XCTAssertThrowsError(try ImageProcessor.jpegUnderBudget(Data([0x00, 0x01])))
    }

    func testJpegUnderBudgetThrowsWhenItCannotFit() throws {
        // No JPEG fits in 1 byte, so even the smallest scale/quality fails the budget.
        let data = try solidPNG(side: 512)
        XCTAssertThrowsError(try ImageProcessor.jpegUnderBudget(data, maxBytes: 1)) { error in
            guard case ImageProcessor.ProcessingError.cannotFitBudget(_, let budget) = error else {
                return XCTFail("expected cannotFitBudget, got \(error)")
            }
            XCTAssertEqual(budget, 1)
        }
    }

    // MARK: - Orientation, alpha, and metadata

    private func solidCGImage(width: Int, height: Int) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func encoded(_ image: CGImage, as type: UTType,
                         properties: [CFString: Any] = [:]) throws -> Data {
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    /// Average colour of the decoded image, drawn into a single pixel.
    private func averagePixel(of data: Data) throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2])
    }

    func testExifOrientationIsBakedInUpright() throws {
        // 80×40 landscape pixels tagged EXIF orientation 6 (rotate 90° CW to
        // display): an upright re-encode must come out 40×80 portrait.
        let fixture = try encoded(solidCGImage(width: 80, height: 40), as: .jpeg,
                                  properties: [kCGImagePropertyOrientation: 6])
        let output = try ImageProcessor.jpegUnderBudget(fixture, maxBytes: 10_000_000)
        let props = try properties(of: output)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 40)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 80)
        // No orientation tag may remain, or a viewer would rotate a second time.
        let orientation = props[kCGImagePropertyOrientation] as? UInt32
        XCTAssertTrue(orientation == nil || orientation == 1, "unexpected orientation \(String(describing: orientation))")
    }

    func testTransparencyFlattensOntoWhite() throws {
        // Fully transparent PNG: JPEG has no alpha, so the pixels must land on
        // white, not black.
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 32, height: 32))
        let png = try encoded(XCTUnwrap(context.makeImage()), as: .png)
        let output = try ImageProcessor.jpegUnderBudget(png, maxBytes: 10_000_000)
        let pixel = try averagePixel(of: output)
        XCTAssertGreaterThan(pixel.r, 240)
        XCTAssertGreaterThan(pixel.g, 240)
        XCTAssertGreaterThan(pixel.b, 240)
    }

    func testOutputStripsGPSAndCameraMetadata() throws {
        let fixture = try encoded(solidCGImage(width: 32, height: 32), as: .jpeg, properties: [
            // ImageIO drops GPS coordinates without hemisphere refs, so the
            // fixture must include them for the sanity check below to hold.
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.5074,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 0.1278,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:18 12:00:00",
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "TestCam",
            ] as [CFString: Any],
        ])
        // The fixture really carries what the processor must strip.
        XCTAssertNotNil(try properties(of: fixture)[kCGImagePropertyGPSDictionary])

        let output = try ImageProcessor.jpegUnderBudget(fixture, maxBytes: 10_000_000)
        let props = try properties(of: output)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal])
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake])
    }

    func testQualityLadderDescendsToDocumentedFloor() {
        // The 0.4 pass must actually run before the loop moves to a smaller scale.
        XCTAssertEqual(ImageProcessor.qualityLadder.first, 0.9)
        XCTAssertEqual(ImageProcessor.qualityLadder.last, 0.4)
        XCTAssertEqual(ImageProcessor.qualityLadder,
                       ImageProcessor.qualityLadder.sorted(by: >))
    }
}
