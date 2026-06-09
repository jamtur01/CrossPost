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

    func testRemoteHTTPIsRejected() {
        // A plain-http remote instance would send the bearer token in cleartext.
        XCTAssertNil(normalized("http://mastodon.example.com"))
    }

    func testLoopbackHTTPIsPreserved() {
        XCTAssertEqual(normalized("http://127.0.0.1:3000"), URL(string: "http://127.0.0.1:3000"))
    }

    func testNonWebSchemeIsRejected() {
        XCTAssertNil(normalized("ftp://hachyderm.io"))
    }

    func testEmptyOrWhitespaceIsNil() {
        XCTAssertNil(normalized(""))
        XCTAssertNil(normalized("   "))
    }

    func testSchemeWithoutHostIsNil() {
        XCTAssertNil(normalized("https://"))
    }
}

@MainActor
final class AccountStoreCredentialTests: XCTestCase {
    override func tearDown() {
        let store = AccountStore(credentials: EphemeralSecretStore())
        store.mastodonInstanceURL = ""
        store.mastodonUsername = ""
        store.blueskyHandle = ""
        super.tearDown()
    }

    func testTokenPersistsAndEmptyClearsIt() {
        let secrets = EphemeralSecretStore()
        let store = AccountStore(credentials: secrets)

        store.mastodonToken = "abc"
        XCTAssertEqual(store.mastodonToken, "abc")
        XCTAssertEqual(try? secrets.load(account: "mastodon-token"), "abc")

        store.mastodonToken = ""
        XCTAssertEqual(store.mastodonToken, "")
        XCTAssertNil(try? secrets.load(account: "mastodon-token"))
    }

    func testHasMastodonRequiresInstanceAndToken() {
        let store = AccountStore(credentials: EphemeralSecretStore())
        store.mastodonInstanceURL = "hachyderm.io"
        XCTAssertFalse(store.hasMastodon)
        store.mastodonToken = "token"
        XCTAssertTrue(store.hasMastodon)
    }

    func testSaveMastodonTrimsInstanceAndStoresToken() throws {
        let store = AccountStore(credentials: EphemeralSecretStore())
        try store.saveMastodon(instanceURL: "  hachyderm.io \n", token: "t",
                               maxChars: 500, username: "me")
        XCTAssertEqual(store.mastodonInstanceURL, "hachyderm.io")
        XCTAssertEqual(store.mastodonUsername, "me")
        XCTAssertTrue(store.hasMastodon)
    }

    func testSaveBlueskyTrimsHandleAndStoresPassword() throws {
        let store = AccountStore(credentials: EphemeralSecretStore())
        try store.saveBluesky(handle: " alice.bsky.social ", appPassword: "pw")
        XCTAssertEqual(store.blueskyHandle, "alice.bsky.social")
        XCTAssertTrue(store.hasBluesky)
    }
}
