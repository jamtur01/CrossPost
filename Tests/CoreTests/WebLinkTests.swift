import XCTest
@testable import CrossPost

final class WebLinkTests: XCTestCase {
    func testAllowsHTTPAndHTTPS() {
        XCTAssertTrue(WebLink.isOpenable(URL(string: "https://example.com")!))
        XCTAssertTrue(WebLink.isOpenable(URL(string: "http://example.com")!))
        XCTAssertTrue(WebLink.isOpenable(URL(string: "HTTPS://EXAMPLE.COM")!))
    }

    func testRejectsDangerousSchemes() {
        for raw in ["file:///etc/passwd", "smb://server/share", "ftp://host/x",
                    "javascript:alert(1)", "mailto:a@b.com", "x-evil-app://run"] {
            XCTAssertFalse(WebLink.isOpenable(URL(string: raw)!), "\(raw) should be rejected")
        }
    }

    func testRejectsSchemelessURL() {
        XCTAssertFalse(WebLink.isOpenable(URL(string: "example.com/path")!))
    }
}
