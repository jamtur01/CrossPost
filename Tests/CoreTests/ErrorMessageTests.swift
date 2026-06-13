import XCTest
import ATProtoKit
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

    // MARK: ATProtoKit mapping
    //
    // ATProtoKit's errors don't conform to `LocalizedError`, so without mapping they
    // bridge to "The operation couldn't be completed. (ATProtoKit.ATAPIError error 0.)".

    private func assertReadable(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(message.contains("error 0"), "leaked the NSError bridge string", file: file, line: line)
        XCTAssertFalse(message.lowercased().contains("couldn't be completed"),
                       "leaked the generic NSError description", file: file, line: line)
        XCTAssertFalse(message.isEmpty, file: file, line: line)
    }

    func testUnknownAPIErrorUsesItsServerMessage() {
        let error = ATAPIError.unknown(error: "Something specific went wrong")
        XCTAssertEqual(error.userMessage, "Something specific went wrong")
    }

    func testUnknownAPIErrorWithoutMessageFallsBackToReadableText() {
        let error = ATAPIError.unknown(error: nil)
        assertReadable(error.userMessage)
        XCTAssertEqual(error.userMessage, "An unexpected server error occurred.")
    }

    func testTransientGatewayErrorsGetFriendlyText() {
        for error in [ATAPIError.badGateway, .serviceUnavailable, .gatewayTimeout] {
            assertReadable(error.userMessage)
            XCTAssertEqual(error.userMessage, "The server is temporarily unavailable. Please try again.")
        }
    }

    func testImageTooLargeErrorIsReadable() {
        let error = ATProtoBluesky.ATBlueskyError.imageTooLarge
        assertReadable(error.userMessage)
        XCTAssertEqual(error.userMessage, "That image is too large to upload.")
    }

    func testReplyReferenceErrorSurfacesItsMessage() {
        let error = ATProtoBluesky.ATProtoBlueskyError.invalidReplyReference(message: "Parent was deleted")
        assertReadable(error.userMessage)
        XCTAssertEqual(error.userMessage, "Parent was deleted")
    }

    func testExpiredSessionErrorPointsToReconnect() {
        let error = ATProtocolConfiguration.ATProtocolConfigurationError.tokensExpired(message: "expired")
        assertReadable(error.userMessage)
        XCTAssertEqual(error.userMessage, "Your session expired. Reconnect the account in Settings.")
    }

    func testOtherATProtoErrorsGetGenericText() {
        // A request-prep error (no server payload) still beats "error 0".
        assertReadable(ATRequestPrepareError.missingActiveSession.userMessage)
    }
}
