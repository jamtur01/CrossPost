import XCTest
import TootSDK
import ATProtoKit
@testable import CrossPost

/// The outgoing mappings from CrossPost's platform-neutral enums onto the SDK
/// types used when posting, reporting, and editing.
final class OutgoingMappingTests: XCTestCase {
    func testVisibilityMapsOntoTootSDK() {
        XCTAssertEqual(PostVisibility.public.tootVisibility, .public)
        XCTAssertEqual(PostVisibility.unlisted.tootVisibility, .unlisted)
        XCTAssertEqual(PostVisibility.private.tootVisibility, .private)
        XCTAssertEqual(PostVisibility.direct.tootVisibility, .direct)
    }

    func testReportReasonMapsOntoMastodonCategory() {
        XCTAssertEqual(ReportReason.spam.mastodonCategory, .spam)
        XCTAssertEqual(ReportReason.harassment.mastodonCategory, .abusive)
        XCTAssertEqual(ReportReason.misleading.mastodonCategory, .other)
        XCTAssertEqual(ReportReason.sexual.mastodonCategory, .sensitive)
        XCTAssertEqual(ReportReason.illegal.mastodonCategory, .legal)
        XCTAssertEqual(ReportReason.other.mastodonCategory, .other)
    }

    func testReportReasonMapsOntoBlueskyReason() {
        XCTAssertEqual(ReportReason.spam.blueskyReason, .spam)
        XCTAssertEqual(ReportReason.harassment.blueskyReason, .rude)
        XCTAssertEqual(ReportReason.misleading.blueskyReason, .misleading)
        XCTAssertEqual(ReportReason.sexual.blueskyReason, .sexual)
        XCTAssertEqual(ReportReason.illegal.blueskyReason, .violation)
        XCTAssertEqual(ReportReason.other.blueskyReason, .other)
    }
}
