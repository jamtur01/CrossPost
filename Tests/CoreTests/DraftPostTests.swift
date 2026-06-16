import XCTest
@testable import CrossPost

final class DraftPostTests: XCTestCase {
    func testDefaultDraftIsEmpty() {
        XCTAssertTrue(DraftPost().isEmpty)
    }

    func testWhitespaceOnlyTextIsEmpty() {
        XCTAssertTrue(DraftPost(text: "  \n\t ").isEmpty)
    }

    func testNonBlankTextIsNotEmpty() {
        XCTAssertFalse(DraftPost(text: "hi").isEmpty)
    }

    func testAttachmentAloneIsNotEmpty() {
        let attachment = Attachment(imageData: Data([0x01, 0x02]))
        XCTAssertFalse(DraftPost(text: "   ", attachments: [attachment]).isEmpty)
    }

    func testDefaultVisibilityIsPublic() {
        XCTAssertEqual(DraftPost().visibility, .public)
    }
}
