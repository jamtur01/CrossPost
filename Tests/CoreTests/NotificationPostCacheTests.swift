@testable import CrossPost
import XCTest

final class NotificationPostCacheTests: XCTestCase {
    func testFreshPostsAndDeletedPostMissesExpireAfterOneMinute() async {
        let cache = NotificationPostCache()
        let now = Date(timeIntervalSince1970: 100)
        let post = TestFactory.feedPost(id: "post")
        await cache.insert(["post": post], requested: ["post", "deleted"], generation: 0, now: now)

        let fresh = await cache.snapshot(for: ["post", "deleted"], now: now.addingTimeInterval(59))
        XCTAssertEqual(fresh.posts, ["post": post])
        XCTAssertTrue(fresh.missing.isEmpty)
        let expired = await cache.snapshot(for: ["post", "deleted"], now: now.addingTimeInterval(60))
        XCTAssertEqual(Set(expired.missing), ["post", "deleted"])
        XCTAssertEqual(expired.posts["post"], post, "Keep stale previews visible during revalidation")

        await cache.insert([:], requested: ["post"], generation: 0, now: now.addingTimeInterval(60))
        let deleted = await cache.snapshot(for: ["post"], now: now.addingTimeInterval(61))
        XCTAssertTrue(deleted.posts.isEmpty)
        XCTAssertTrue(deleted.missing.isEmpty)
    }

    func testMutationInvalidationRejectsAnOlderHydrationResponse() async {
        let cache = NotificationPostCache()
        let post = TestFactory.feedPost(id: "post")
        let pending = await cache.snapshot(for: ["post"])
        await cache.invalidate("post")
        await cache.insert(["post": post], requested: ["post"], generation: pending.generation)
        let result = await cache.snapshot(for: ["post"])
        XCTAssertEqual(result.missing, ["post"])
        XCTAssertTrue(result.posts.isEmpty)
    }

    func testCacheRetainsAtMostTwoHundredPosts() async {
        let cache = NotificationPostCache()
        let now = Date(timeIntervalSince1970: 100)
        let post = TestFactory.feedPost(id: "post")
        let uris = (0 ..< 201).map { "uri-\($0)" }
        await cache.insert(Dictionary(uniqueKeysWithValues: uris.map { ($0, post) }),
                           requested: uris, generation: 0, now: now)
        let result = await cache.snapshot(for: Set(uris), now: now)
        XCTAssertEqual(result.posts.count, 200)
        XCTAssertEqual(result.missing.count, 1)
    }
}
