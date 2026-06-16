import XCTest
@testable import CrossPost

final class SearchResultsTests: XCTestCase {
    func testIsEmptyOnlyWhenBothEmpty() {
        XCTAssertTrue(SearchResults().isEmpty)
        XCTAssertFalse(SearchResults(posts: [TestFactory.feedPost()]).isEmpty)

        let profile = Profile(id: "1", name: "A", handle: "@a", avatarURL: nil, bannerURL: nil,
                              bio: AttributedString(""), followers: 0, following: 0, posts: 0, webURL: nil)
        XCTAssertFalse(SearchResults(accounts: [profile]).isEmpty)
    }
}
