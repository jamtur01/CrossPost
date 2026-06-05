import XCTest
import AppKit
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

    func testJpegDataRejectsUndecodableInput() {
        XCTAssertThrowsError(try ImageProcessor.jpegData(Data([0x00, 0x01, 0x02, 0x03])))
    }

    func testJpegDataProducesJPEGMagicBytes() throws {
        let output = try ImageProcessor.jpegData(solidPNG(side: 64))
        XCTAssertFalse(output.isEmpty)
        XCTAssertEqual(Array(output.prefix(2)), [0xFF, 0xD8])   // JPEG SOI marker
    }

    func testJpegUnderBudgetStaysWithinBudget() throws {
        let output = try ImageProcessor.jpegUnderBudget(solidPNG(side: 512), maxBytes: 20_000)
        XCTAssertFalse(output.isEmpty)
        XCTAssertLessThanOrEqual(output.count, 20_000)
        XCTAssertEqual(Array(output.prefix(2)), [0xFF, 0xD8])
    }

    func testJpegUnderBudgetRejectsUndecodableInput() {
        XCTAssertThrowsError(try ImageProcessor.jpegUnderBudget(Data([0x00, 0x01])))
    }
}
