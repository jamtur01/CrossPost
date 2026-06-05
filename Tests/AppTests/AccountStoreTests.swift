import XCTest
@testable import CrossPost

final class AccountStoreTests: XCTestCase {
    private func normalized(_ raw: String) -> URL? {
        AccountStore.normalizedMastodonBaseURL(from: raw)
    }

    func testBareHostGetsHTTPSScheme() {
        XCTAssertEqual(normalized("hachyderm.io"), URL(string: "https://hachyderm.io"))
    }

    func testTrailingSlashesDropped() {
        XCTAssertEqual(normalized("https://hachyderm.io///"), URL(string: "https://hachyderm.io"))
    }

    func testSurroundingWhitespaceTrimmed() {
        XCTAssertEqual(normalized("  hachyderm.io \n"), URL(string: "https://hachyderm.io"))
    }

    func testExistingSchemeAndPortPreserved() {
        XCTAssertEqual(normalized("http://localhost:3000"), URL(string: "http://localhost:3000"))
    }

    func testEmptyOrWhitespaceIsNil() {
        XCTAssertNil(normalized(""))
        XCTAssertNil(normalized("   "))
    }

    func testSchemeWithoutHostIsNil() {
        XCTAssertNil(normalized("https://"))
    }
}
