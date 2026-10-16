@testable import CrossPost
import XCTest

final class MentionQueryTests: XCTestCase {
    private func detect(_ text: String, caret: Int? = nil) -> MentionQuery? {
        MentionQuery.detect(in: text, caret: caret ?? (text as NSString).length)
    }

    func testDetectsAtStartAndAfterWhitespace() {
        XCTAssertEqual(detect("@pu"), MentionQuery(range: NSRange(location: 0, length: 3), text: "pu"))
        XCTAssertEqual(detect("hi\n@pup")?.text, "pup")
        XCTAssertEqual(detect("hi @pup")?.range, NSRange(location: 3, length: 4))
    }

    func testNeedsTwoCharacters() {
        XCTAssertNil(detect("@p"))
        XCTAssertNil(detect("@"))
    }

    func testIgnoresEmailsAndWordsWithoutLeadingAt() {
        XCTAssertNil(detect("bob@example.com"))
        XCTAssertNil(detect("hello"))
    }

    func testFullAddressKeepsSecondAt() {
        XCTAssertEqual(detect("@pup@hachyderm")?.text, "pup@hachyderm")
    }

    func testCaretMustEndTheToken() {
        XCTAssertNil(detect("@puppet", caret: 4))
        XCTAssertEqual(detect("@pup more", caret: 4)?.text, "pup")
        XCTAssertNil(detect("@pup ", caret: 5))
    }

    func testEmojiBeforeQueryUsesUTF16Range() {
        let text = "👍 @al"
        XCTAssertEqual(detect(text)?.range, NSRange(location: 3, length: 3))
    }
}
