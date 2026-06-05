import XCTest
@testable import CrossPost

final class ErrorMessageTests: XCTestCase {
    private struct Friendly: LocalizedError {
        var errorDescription: String? { "a friendly message" }
    }

    func testPrefersLocalizedErrorDescription() {
        XCTAssertEqual(Friendly().userMessage, "a friendly message")
    }

    func testFallsBackToLocalizedDescription() {
        let error = NSError(domain: "test", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "the cause"])
        XCTAssertEqual(error.userMessage, "the cause")
    }

    func testUsesProjectErrorDescription() {
        XCTAssertEqual(ImageProcessor.ProcessingError.decodeFailed.userMessage,
                       "Could not read image data")
    }
}
