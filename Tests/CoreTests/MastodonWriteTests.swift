@testable import CrossPost
import TootSDK
import XCTest

/// Drives the Mastodon poster's and feed service's writes through TootSDK against
/// stubbed endpoints.
final class MastodonWriteTests: XCTestCase {
    private let host = URL(string: "https://mastodon-writes.test")!

    private func makeClient() -> TootClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageURLProtocolStub.self]
        return TootClient(session: URLSession(configuration: config), instanceURL: host, accessToken: "token")
    }

    /// Answers `path` with the fixture status, `field` set to `value` when given.
    private func stubStatus(path: String, field: String? = nil, value: Bool = false) throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "mastodon_reply", withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        if let field {
            json[field] = value
        }
        try ImageURLProtocolStub.configure(url: host.appending(path: path),
                                           statusCode: 200, mimeType: "application/json",
                                           data: JSONSerialization.data(withJSONObject: json))
    }

    private func stubMediaUpload() throws {
        try ImageURLProtocolStub.configure(url: host.appending(path: "api/v2/media"),
                                           statusCode: 200, mimeType: "application/json",
                                           data: JSONSerialization.data(withJSONObject: [
                                               "id": "m1", "url": "https://h.io/m1.jpg"
                                           ]))
    }

    /// The `media_ids` values in the latest published status's multipart body, in order.
    private func publishedMediaIDs() throws -> [String] {
        let statuses = host.appending(path: "api/v1/statuses")
        let body = try XCTUnwrap(ImageURLProtocolStub.lastRequestBody(for: statuses))
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        let field = /name="media_ids[^"]*"\r\n(?:[^\r\n]+\r\n)*\r\n([^\r\n]*)\r\n/
        return text.matches(of: field).map { String($0.output.1) }
    }

    /// A thread with images still posts when the instance limit can't be read (the
    /// 0.5.1 fix), falling back to the default, and reads the limit once per poster.
    func testPosterPublishesImagesWhenInstanceInfoCannotBeRead() async throws {
        let instance = host.appending(path: "api/v2/instance")
        ImageURLProtocolStub.configure(url: instance, statusCode: 500, mimeType: "application/json", data: Data())
        try stubMediaUpload()
        try stubStatus(path: "api/v1/statuses")
        let image = Attachment(imageData: TestFactory.imageData())
        let thread = [DraftPost(text: "one", attachments: [image]), DraftPost(text: "two", attachments: [image])]

        let posted = try await MastodonPoster(client: makeClient()).post(thread: thread, continuingFrom: nil)

        XCTAssertEqual(posted.map(\.ref), [.mastodon(statusID: "REPLY-7"), .mastodon(statusID: "REPLY-7")])
        XCTAssertEqual(ImageURLProtocolStub.requestCount(for: instance), 1)
        XCTAssertEqual(ImageURLProtocolStub.requestCount(for: host.appending(path: "api/v2/media")), 2)
    }

    /// Uploaded images reach the published post and the reply, and a post without images
    /// sends none.
    func testPublishedPostsCarryTheirUploadedMedia() async throws {
        ImageURLProtocolStub.configure(url: host.appending(path: "api/v2/instance"), statusCode: 500,
                                       mimeType: "application/json", data: Data())
        try stubMediaUpload()
        try stubStatus(path: "api/v1/statuses")
        let image = Attachment(imageData: TestFactory.imageData())
        let poster = MastodonPoster(client: makeClient())

        _ = try await poster.post(thread: [DraftPost(text: "one", attachments: [image, image])], continuingFrom: nil)
        XCTAssertEqual(try publishedMediaIDs(), ["m1", "m1"])
        _ = try await poster.post(thread: [DraftPost(text: "two")], continuingFrom: nil)
        XCTAssertEqual(try publishedMediaIDs(), [])

        let service = MastodonFeedService(client: makeClient())
        let parent = TestFactory.feedPost(id: "PARENT")
        _ = try await service.reply(to: parent, text: "hi", images: [image], visibility: .public)
        XCTAssertEqual(try publishedMediaIDs(), ["m1"])
        _ = try await service.reply(to: parent, text: "hi", images: [], visibility: .public)
        XCTAssertEqual(try publishedMediaIDs(), [])
    }

    /// Too many images are refused before the limit is read or anything is uploaded, and
    /// a post with no images never asks for the limit.
    func testUploadChecksTheImageCountBeforeAnyRequest() async throws {
        let client = makeClient()
        let none = try await client.uploadJPEGImages([]) {
            XCTFail("no images, so no limit to read")
            return 0
        }
        XCTAssertEqual(none, [])

        let images = (0 ..< 5).map { _ in Attachment(imageData: TestFactory.imageData()) }
        do {
            _ = try await client.uploadJPEGImages(images) {
                XCTFail("too many images, so no limit to read")
                return 0
            }
            XCTFail("expected tooManyImages")
        } catch let MediaValidationError.tooManyImages(target, count, limit) {
            XCTAssertEqual(target, .mastodon)
            XCTAssertEqual(count, 5)
            XCTAssertEqual(limit, 4)
        }
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
        let service = MastodonFeedService(client: makeClient())
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
                try stubStatus(path: "api/v1/statuses/REPLY-7/\(endpoint)", field: toggle.field, value: !requested)
                var expected = post
                expected[keyPath: toggle.flag] = !requested
                let result = try await toggle.run(requested, post)
                XCTAssertEqual(result, expected, "\(endpoint) must keep the server's \(toggle.field)")
            }
        }
    }
}
