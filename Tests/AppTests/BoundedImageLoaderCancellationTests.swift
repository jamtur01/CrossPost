import AppKit
@testable import CrossPost
import Foundation
import XCTest

final class BoundedImageLoaderCancellationTests: XCTestCase {
    func testCancellingOneWaiterDoesNotCancelSharedLoad() async throws {
        let url = uniqueURL()
        try ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/png",
            data: pngData(width: 64, height: 64),
            options: .init(delay: 0.08)
        )
        let loader = makeLoader()
        let request = thumbnailRequest(url: url)
        let cancelled = Task { try await loader.image(for: request) }
        let remaining = Task { try await loader.image(for: request) }
        try await waitUntil { await loader.waiterCount(for: request) == 2 }

        cancelled.cancel()

        do {
            _ = try await cancelled.value
            XCTFail("The cancelled waiter should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
        _ = try await remaining.value
        XCTAssertEqual(ImageURLProtocolStub.requestCount(for: url), 1)
    }

    func testCancellingLastWaiterCancelsSourceRequest() async throws {
        let url = uniqueURL()
        try ImageURLProtocolStub.configure(
            url: url,
            statusCode: 200,
            mimeType: "image/png",
            data: pngData(width: 64, height: 64),
            options: .init(delay: 0.5)
        )
        let loader = makeLoader()
        let request = thumbnailRequest(url: url)
        let load = Task { try await loader.image(for: request) }
        try await waitUntil { ImageURLProtocolStub.requestCount(for: url) == 1 }

        load.cancel()
        do {
            _ = try await load.value
            XCTFail("The cancelled waiter should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }

        try await waitUntil { ImageURLProtocolStub.stopCount(for: url) > 0 }
        XCTAssertEqual(ImageURLProtocolStub.deliveredByteCount(for: url), 0)
    }

    func testCancelledSourceCannotCompleteReplacementRequest() async throws {
        let url = uniqueURL()
        let dataClient = ControllableImageDataClient()
        let loader = BoundedImageLoader(dataClient: dataClient)
        let request = thumbnailRequest(url: url)
        let cancelled = Task { try await loader.image(for: request) }
        try await waitUntil { await dataClient.requestCount == 1 }

        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("The cancelled waiter should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }

        let replacement = Task { try await loader.image(for: request) }
        try await waitUntil {
            let requestCount = await dataClient.requestCount
            let waiterCount = await loader.waiterCount(for: request)
            return requestCount == 2 && waiterCount == 1
        }
        await dataClient.failRequest(at: 0, with: CancellationError())
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        let replacementWaiterCount = await loader.waiterCount(for: request)
        XCTAssertEqual(replacementWaiterCount, 1)
        try await dataClient.succeedRequest(at: 1, with: pngData(width: 64, height: 64))
        _ = try await replacement.value
    }

    private func makeLoader() -> BoundedImageLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocolStub.self]
        return BoundedImageLoader(configuration: configuration)
    }

    private func uniqueURL() -> URL {
        URL(string: "https://example.test/\(UUID().uuidString)")!
    }

    private func thumbnailRequest(url: URL) -> ImageRequest {
        ImageRequest(
            url: url,
            representation: .thumbnail,
            targetSize: CGSize(width: 64, height: 64)
        )
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0 ..< 200 {
            if await predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Condition was not met before timeout")
    }

    private func pngData(width: Int, height: Int) throws -> Data {
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
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

private actor ControllableImageDataClient: BoundedImageDataLoading {
    private var continuations: [CheckedContinuation<Data, Error>] = []

    var requestCount: Int {
        continuations.count
    }

    func data(from _: URL, limit _: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func failRequest(at index: Int, with error: any Error) {
        continuations[index].resume(throwing: error)
    }

    func succeedRequest(at index: Int, with data: Data) {
        continuations[index].resume(returning: data)
    }
}
