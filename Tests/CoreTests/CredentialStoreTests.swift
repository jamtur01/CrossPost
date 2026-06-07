import XCTest
@testable import CrossPost

/// Covers `EphemeralSecretStore`, the in-process `SecretStoring` used as the
/// Keychain substitute under test. The real `CredentialStore` talks to the
/// Keychain (an external boundary) and is exercised through the running app,
/// not unit tests.
final class CredentialStoreTests: XCTestCase {
    func testSaveThenLoadReturnsValue() throws {
        let store = EphemeralSecretStore()
        try store.save("token-123", account: "mastodon")
        XCTAssertEqual(try store.load(account: "mastodon"), "token-123")
    }

    func testLoadMissingAccountReturnsNil() throws {
        let store = EphemeralSecretStore()
        XCTAssertNil(try store.load(account: "absent"))
    }

    func testSaveOverwritesExistingValue() throws {
        let store = EphemeralSecretStore()
        try store.save("old", account: "bluesky")
        try store.save("new", account: "bluesky")
        XCTAssertEqual(try store.load(account: "bluesky"), "new")
    }

    func testDeleteRemovesValue() throws {
        let store = EphemeralSecretStore()
        try store.save("secret", account: "bluesky")
        try store.delete(account: "bluesky")
        XCTAssertNil(try store.load(account: "bluesky"))
    }

    func testDeleteMissingAccountIsANoOp() {
        let store = EphemeralSecretStore()
        XCTAssertNoThrow(try store.delete(account: "absent"))
    }

    func testAccountsAreIsolated() throws {
        let store = EphemeralSecretStore()
        try store.save("m", account: "mastodon")
        try store.save("b", account: "bluesky")
        try store.delete(account: "mastodon")
        XCTAssertNil(try store.load(account: "mastodon"))
        XCTAssertEqual(try store.load(account: "bluesky"), "b")
    }
}
