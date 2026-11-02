@testable import CrossPost
import TootSDK
import XCTest

/// Drives the Mastodon service's writes through TootSDK against stubbed endpoints.
final class MastodonFeedServiceWriteTests: XCTestCase {
    private let host = URL(string: "https://mastodon-writes.test")!

    private func makeService() -> MastodonFeedService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageURLProtocolStub.self]
        let session = URLSession(configuration: config)
        return MastodonFeedService(client: TootClient(session: session, instanceURL: host, accessToken: "token"))
    }

    /// Answers `POST /api/v1/statuses/REPLY-7/<action>` with the status, `field` set to `value`.
    private func stubStatus(_ action: String, field: String, value: Bool) throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "mastodon_reply", withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        json[field] = value
        try ImageURLProtocolStub.configure(url: host.appending(path: "api/v1/statuses/REPLY-7/\(action)"),
                                           statusCode: 200, mimeType: "application/json",
                                           data: JSONSerialization.data(withJSONObject: json))
    }

    private struct Toggle {
        let endpoints: (on: String, off: String)
        let field: String
        let flag: WritableKeyPath<FeedPost, Bool>
        let run: (Bool, FeedPost) async throws -> FeedPost
    }

    /// Each toggle calls its own endpoint and keeps the state the server reports, even
    /// when it disagrees with the request, leaving the post's other flags alone.
    func testTogglesCallTheirEndpointAndKeepTheServersState() async throws {
        let service = makeService()
        let post = TestFactory.feedPost(id: "REPLY-7")
        let toggles = [
            Toggle(endpoints: ("favourite", "unfavourite"), field: "favourited", flag: \.isLiked,
                   run: service.setLiked),
            Toggle(endpoints: ("reblog", "unreblog"), field: "reblogged", flag: \.isReposted,
                   run: service.setReposted),
            Toggle(endpoints: ("bookmark", "unbookmark"), field: "bookmarked", flag: \.isBookmarked,
                   run: service.setBookmarked),
            Toggle(endpoints: ("pin", "unpin"), field: "pinned", flag: \.isPinned, run: service.setPinned)
        ]
        for toggle in toggles {
            for requested in [true, false] {
                let endpoint = requested ? toggle.endpoints.on : toggle.endpoints.off
                try stubStatus(endpoint, field: toggle.field, value: !requested)
                var expected = post
                expected[keyPath: toggle.flag] = !requested
                let result = try await toggle.run(requested, post)
                XCTAssertEqual(result, expected, "\(endpoint) must keep the server's \(toggle.field)")
            }
        }
    }
}
