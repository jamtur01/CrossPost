import XCTest
import TootSDK
@testable import CrossPost

/// Fixture-decoded tests for the Mastodon feed mapping. The fixtures are decoded
/// with a `JSONDecoder` configured like TootSDK's internal `TootDecoder`
/// (snake_case keys + its multi-format date strategy), since that initializer
/// isn't accessible from here.
final class MastodonMappingTests: XCTestCase {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = withFraction.date(from: string) ?? plain.date(from: string) { return date }
            if let seconds = TimeInterval(string) { return Date(timeIntervalSince1970: seconds) }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(), debugDescription: "bad date: \(string)")
        }
        return decoder
    }()

    private func decodePost(_ name: String) throws -> Post {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
                                "missing fixture \(name).json")
        return try Self.decoder.decode(Post.self, from: Data(contentsOf: url))
    }

    func testBoostUsesOuterIDWhileNativeRefAndContentComeFromTheBoostedStatus() throws {
        let mapped = MastodonFeedService.feedPost(from: try decodePost("mastodon_boost"))

        XCTAssertEqual(mapped.id, "mastodon:BOOST-1")               // outer entry id stays distinct
        XCTAssertEqual(mapped.boostedBy, "Bob Booster")             // attributed to the reposter
        XCTAssertEqual(mapped.authorHandle, "@alice@h.io")          // content is the original author's
        XCTAssertEqual(String(mapped.text.characters), "original toot")
        XCTAssertEqual(mapped.likeCount, 8)                         // counts from the boosted status

        guard case .mastodon(let statusID) = mapped.nativeRef else { return XCTFail("expected mastodon ref") }
        XCTAssertEqual(statusID, "INNER-9")                         // like/reply target the real status
    }

    func testReplyInheritsVisibilitySpoilerAndSensitive() throws {
        let mapped = MastodonFeedService.feedPost(from: try decodePost("mastodon_reply"))

        XCTAssertEqual(mapped.visibility, "private")
        XCTAssertEqual(mapped.spoilerText, "content warning")
        XCTAssertTrue(mapped.isSensitive)
        XCTAssertTrue(mapped.isReply)
    }
}
