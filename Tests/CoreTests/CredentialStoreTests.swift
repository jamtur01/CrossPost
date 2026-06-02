import XCTest
@testable import CrossPost

final class CredentialStoreTests: XCTestCase {
    // Unique service per run so tests are isolated and self-cleaning.
    private func makeStore() -> CredentialStore {
        CredentialStore(service: "net.kartar.crosspost.tests.\(UUID().uuidString)")
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = makeStore()
        defer { try? store.delete(account: "token") }
        try store.save("secret-123", account: "token")
        XCTAssertEqual(try store.load(account: "token"), "secret-123")
    }

    func testSaveOverwritesExistingValue() throws {
        let store = makeStore()
        defer { try? store.delete(account: "token") }
        try store.save("first", account: "token")
        try store.save("second", account: "token")
        XCTAssertEqual(try store.load(account: "token"), "second")
    }

    func testLoadMissingReturnsNil() throws {
        let store = makeStore()
        XCTAssertNil(try store.load(account: "absent"))
    }

    func testDeleteRemovesValue() throws {
        let store = makeStore()
        try store.save("x", account: "token")
        try store.delete(account: "token")
        XCTAssertNil(try store.load(account: "token"))
    }

    func testDeleteMissingDoesNotThrow() throws {
        let store = makeStore()
        XCTAssertNoThrow(try store.delete(account: "absent"))
    }
}
