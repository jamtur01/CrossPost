import XCTest
import ATProtoKit
@testable import CrossPost

/// The account-report subject is built by decoding the lexicon JSON (ATProtoKit
/// exposes no public initializer for repoRef), so it's worth pinning down.
final class BlueskyReportSubjectTests: XCTestCase {
    func testAccountReportSubjectIsRepoRefWithDID() throws {
        let subject = try BlueskyFeedService.accountReportSubject(did: "did:plc:abc123")
        guard case .repositoryReference(let ref) = subject else {
            return XCTFail("expected a repository reference subject")
        }
        XCTAssertEqual(ref.repositoryDID, "did:plc:abc123")
    }

    func testAccountReportSubjectSurvivesDIDWithQuoteAndBackslash() throws {
        // The subject is built through JSONEncoder, so characters that would
        // break naive string-interpolated JSON must round-trip intact.
        let hostile = #"did:plc:a"b\c"#
        let subject = try BlueskyFeedService.accountReportSubject(did: hostile)
        guard case .repositoryReference(let ref) = subject else {
            return XCTFail("expected a repository reference subject")
        }
        XCTAssertEqual(ref.repositoryDID, hostile)
    }
}
