import AppKit
@testable import CrossPost
import Foundation
import XCTest

final class BoundedImageLoaderTests: XCTestCase {
    func testConcurrentIdenticalRequestsCoalesce() async throws {
        let url = uniqueURL()
        try ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/png",
            data: pngData(width: 64, height: 32),
            options: .init(delay: 0.05)
        )
        let loader = makeLoader()
        let request = ImageRequest(
            url: url,
            representation: .thumbnail,
            targetSize: CGSize(width: 64, height: 32)
        )

        async let first = loader.image(for: request)
        async let second = loader.image(for: request)
        _ = try await (first, second)

        XCTAssertEqual(ImageURLProtocolStub.requestCount(for: url), 1)
    }

    func testCacheKeySeparatesTargetSizes() async throws {
        let url = uniqueURL()
        try ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/png",
            data: pngData(width: 128, height: 128)
        )
        let loader = makeLoader()
        let small = ImageRequest(
            url: url,
            representation: .thumbnail,
            targetSize: CGSize(width: 32, height: 32)
        )
        let large = ImageRequest(
            url: url,
            representation: .thumbnail,
            targetSize: CGSize(width: 96, height: 96)
        )

        let smallImage = try await loader.image(for: small)
        let largeImage = try await loader.image(for: large)

        let smallWidth = try XCTUnwrap(smallImage.representations.first).pixelsWide
        let largeWidth = try XCTUnwrap(largeImage.representations.first).pixelsWide
        XCTAssertLessThan(smallWidth, largeWidth)
        XCTAssertEqual(ImageURLProtocolStub.requestCount(for: url), 2)
    }

    func testStaticCacheCostUsesDecodedRasterBytes() async throws {
        let url = uniqueURL()
        let data = try pngData(width: 64, height: 32)
        ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/png",
            data: data
        )
        let loader = makeLoader()
        let request = ImageRequest(
            url: url,
            representation: .thumbnail,
            targetSize: CGSize(width: 64, height: 32)
        )

        _ = try await loader.image(for: request)
        XCTAssertEqual(loader.cachedCost(for: request), 64 * 32 * 4)
        XCTAssertNotEqual(loader.cachedCost(for: request), data.count)
    }

    func testRejectsBadHTTPStatus() async {
        let url = uniqueURL()
        ImageURLProtocolStub.configure(
            url: url,
            statusCode: 503,
            mimeType: "image/png",
            data: Data()
        )
        let loader = makeLoader()

        await assertLoadError(
            .invalidStatus(503),
            loader: loader,
            request: thumbnailRequest(url: url)
        )
    }

    func testRejectsNonImageMIMEType() async {
        let url = uniqueURL()
        ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "text/html",
            data: Data("<html></html>".utf8)
        )
        let loader = makeLoader()

        await assertLoadError(
            .invalidMIMEType("text/html"),
            loader: loader,
            request: thumbnailRequest(url: url)
        )
    }

    func testRejectsUndecodableImagePayload() async {
        let url = uniqueURL()
        ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/png",
            data: Data("not an image".utf8)
        )
        let loader = makeLoader()

        await assertLoadError(
            .invalidDimensions,
            loader: loader,
            request: thumbnailRequest(url: url)
        )
    }

    func testRejectsOversizedDeclaredContentLength() async {
        let url = uniqueURL()
        let limit = ImageRepresentation.avatar.maxDownloadBytes
        ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/png",
            data: Data(count: 1024),
            options: .init(declaredContentLength: limit + 1)
        )
        let loader = makeLoader()
        let request = ImageRequest(
            url: url,
            representation: .avatar,
            targetSize: CGSize(width: 64, height: 64)
        )

        await assertLoadError(
            .contentLengthExceeded(limit: limit, actual: Int64(limit + 1)),
            loader: loader,
            request: request
        )
    }

    func testRejectsStreamingResponseAtByteLimit() async {
        let url = uniqueURL()
        let limit = ImageRepresentation.avatar.maxDownloadBytes
        ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/png",
            data: Data(count: limit + 1),
            options: .init(chunks: 3, includesContentLength: false)
        )
        let loader = makeLoader()
        let request = ImageRequest(
            url: url,
            representation: .avatar,
            targetSize: CGSize(width: 64, height: 64)
        )

        await assertLoadError(
            .responseTooLarge(limit: limit),
            loader: loader,
            request: request
        )
        XCTAssertLessThanOrEqual(ImageURLProtocolStub.deliveredByteCount(for: url), limit + 1)
    }

    func testAnimatedRequestsCoalesceAndEnforceByteLimit() async throws {
        let url = uniqueURL()
        try ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/gif",
            data: gifData(width: 16, height: 16),
            options: .init(delay: 0.05)
        )
        let loader = makeLoader()
        let request = ImageRequest(
            url: url,
            representation: .animated,
            targetSize: CGSize(width: 320, height: 240)
        )

        async let first = loader.image(for: request)
        async let second = loader.image(for: request)
        _ = try await (first, second)
        XCTAssertEqual(ImageURLProtocolStub.requestCount(for: url), 1)

        let oversizedURL = try XCTUnwrap(
            URL(string: "https://example.test/\(UUID().uuidString)/oversized.gif")
        )
        ImageURLProtocolStub.configure(
            url: oversizedURL,
            statusCode: 200,
            mimeType: "image/gif",
            data: Data(),
            options: .init(
                declaredContentLength: ImageRepresentation.animated.maxDownloadBytes + 1
            )
        )
        let oversized = ImageRequest(
            url: oversizedURL,
            representation: .animated,
            targetSize: CGSize(width: 320, height: 240)
        )
        await assertLoadError(
            .contentLengthExceeded(
                limit: ImageRepresentation.animated.maxDownloadBytes,
                actual: Int64(ImageRepresentation.animated.maxDownloadBytes + 1)
            ),
            loader: loader,
            request: oversized
        )
    }

    func testRejectsAnimatedSourceLargerThanRequestedTarget() async throws {
        let url = uniqueURL()
        try ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/gif",
            data: gifData(width: 64, height: 64)
        )
        let loader = makeLoader()
        let request = ImageRequest(
            url: url,
            representation: .animated,
            targetSize: CGSize(width: 32, height: 32)
        )

        await assertLoadError(
            .decodedSizeExceeded(limit: 32 * 32 * 4),
            loader: loader,
            request: request
        )
    }
}

private extension BoundedImageLoaderTests {
    func makeLoader() -> BoundedImageLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocolStub.self]
        return BoundedImageLoader(configuration: configuration)
    }

    func uniqueURL() -> URL {
        URL(string: "https://example.test/\(UUID().uuidString)")!
    }

    func thumbnailRequest(url: URL) -> ImageRequest {
        ImageRequest(
            url: url,
            representation: .thumbnail,
            targetSize: CGSize(width: 64, height: 64)
        )
    }

    func assertLoadError(
        _ expected: ImageLoadingError,
        loader: BoundedImageLoader,
        request: ImageRequest
    ) async {
        do {
            _ = try await loader.image(for: request)
            XCTFail("Expected \(expected)")
        } catch let error as ImageLoadingError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func waitUntil(_ predicate: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0 ..< 200 {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Condition was not met before timeout")
    }

    func pngData(width: Int, height: Int) throws -> Data {
        try bitmapData(width: width, height: height, type: .png)
    }

    func gifData(width: Int, height: Int) throws -> Data {
        try bitmapData(width: width, height: height, type: .gif)
    }

    func bitmapData(
        width: Int,
        height: Int,
        type: NSBitmapImageRep.FileType
    ) throws -> Data {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        return try XCTUnwrap(bitmap.representation(using: type, properties: [:]))
    }
}
