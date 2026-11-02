import ATProtoKit
@testable import CrossPost
import XCTest

/// The Bluesky service's record writes, on a kit with no session whose requests all
/// fail: a call that reaches the network throws, so a passing call wrote nothing.
final class BlueskyFeedServiceWriteTests: XCTestCase {
    private func makeService() async -> BlueskyFeedService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageURLProtocolStub.self] // nothing stubbed: every request fails
        let kit = await ATProtoKit(apiClientConfiguration: .init(urlSessionConfiguration: config))
        return BlueskyFeedService(kit: kit, bluesky: ATProtoBluesky(atProtoKitInstance: kit), handle: "me.test")
    }

    /// Liking or reposting again with the record already known keeps that record
    /// instead of creating a second one that undo could never reach.
    func testRepeatedLikeOrRepostKeepsItsRecord() async throws {
        let service = await makeService()
        var post = TestFactory.feedPost(target: .bluesky)
        post.isLiked = true
        post.likeRecordURI = "at://did:plc:me/app.bsky.feed.like/1"
        post.isReposted = true
        post.repostRecordURI = "at://did:plc:me/app.bsky.feed.repost/1"

        let liked = try await service.setLiked(true, on: post)
        XCTAssertEqual(liked, post)
        let reposted = try await service.setReposted(true, on: post)
        XCTAssertEqual(reposted, post)
    }
}
