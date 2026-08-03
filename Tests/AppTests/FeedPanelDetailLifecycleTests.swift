@testable import CrossPost
import XCTest

@MainActor
final class FeedPanelDetailLifecycleTests: FeedPanelTestCase {
    // MARK: Quote / edit / report / saved feeds

    private func expectRefreshNotification() -> (count: () -> Int, stop: () -> Void) {
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: .crossPostDidPost, object: nil, queue: nil
        ) { _ in count += 1 }
        return ({ count }, { NotificationCenter.default.removeObserver(token) })
    }

    func testQuoteForwardsArgsAndRefreshesOnce() async throws {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let refresh = expectRefreshNotification()
        defer { refresh.stop() }

        _ = try await model.quote(post: TestFactory.feedPost(), text: "nice", visibility: .unlisted)

        XCTAssertEqual(fake.quoteCalls.count, 1)
        XCTAssertEqual(fake.quoteCalls.first?.text, "nice")
        XCTAssertEqual(fake.quoteCalls.first?.visibility, .unlisted)
        XCTAssertEqual(refresh.count(), 1)
    }

    func testEditForwardsArgsAndRefreshesOnce() async throws {
        let fake = FakeFeedService()
        let model = makeModel(fake)
        let refresh = expectRefreshNotification()
        defer { refresh.stop() }

        _ = try await model.edit(post: TestFactory.feedPost(), text: "fixed", spoiler: "cw")

        XCTAssertEqual(fake.editCalls.count, 1)
        XCTAssertEqual(fake.editCalls.first?.text, "fixed")
        XCTAssertEqual(fake.editCalls.first?.spoiler, "cw")
        XCTAssertEqual(refresh.count(), 1)
    }

    func testReportForwardsToService() async throws {
        let fake = FakeFeedService()
        let model = makeModel(fake)

        try await model.report(post: TestFactory.feedPost(), reason: .spam, comment: "bot")

        XCTAssertEqual(fake.reportPostCalls.count, 1)
        XCTAssertEqual(fake.reportPostCalls.first?.reason, .spam)
        XCTAssertEqual(fake.reportPostCalls.first?.comment, "bot")
    }

    func testBookmarkedLikedAndPinnedPostsReadFromService() async throws {
        let fake = FakeFeedService()
        var bookmarked = TestFactory.feedPost(id: "b1"); bookmarked.isBookmarked = true
        var liked = TestFactory.feedPost(id: "l1"); liked.isLiked = true
        var pinned = TestFactory.feedPost(id: "p1"); pinned.isPinned = true
        fake.feed = [bookmarked, liked, pinned, TestFactory.feedPost(id: "plain")]
        let model = makeModel(fake)

        let bookmarks = try await model.bookmarkedPosts()
        let likes = try await model.likedPosts()
        let pins = try await model.pinnedPosts(id: "anyone")

        XCTAssertEqual(bookmarks.map(\.id), ["b1"])
        XCTAssertEqual(likes.map(\.id), ["l1"])
        XCTAssertEqual(pins.map(\.id), ["p1"])
    }

    func testDetailFetchesPropagateErrors() async {
        let fake = FakeFeedService()
        fake.failLoad = true
        let model = makeModel(fake)

        // The detail views rely on these throwing so they can show a retry state.
        var profileThrew = false, postsThrew = false
        do { _ = try await model.profile(id: "x") } catch { profileThrew = true }
        do { _ = try await model.authorPosts(id: "x") } catch { postsThrew = true }

        XCTAssertTrue(profileThrew)
        XCTAssertTrue(postsThrew)
    }

    func testRelationshipFailurePropagatesWithoutFabricatedState() async {
        let fake = FakeFeedService()
        fake.failRelationship = true
        let model = makeModel(fake)

        do {
            _ = try await model.relationship(with: "actor")
            XCTFail("relationship failure must propagate")
        } catch {
            XCTAssertTrue(error is FakeFeedService.FakeError)
        }
    }

    func testRelationshipFailureLeavesControlsUnresolvedAndRetryable() {
        var state = ProfilePartialLoadState()

        state.beginRelationshipLoad()
        state.finishRelationship(.failure(FakeFeedService.FakeError.boom))

        XCTAssertNil(state.relationship)
        XCTAssertNotNil(state.relationshipError)

        state.beginRelationshipLoad()
        state.finishRelationship(.success(AccountRelationship(isFollowing: true)))
        XCTAssertEqual(state.relationship?.isFollowing, true)
        XCTAssertNil(state.relationshipError)
    }

    func testPinnedFailurePreservesPinsAndIndependentAuthorPosts() async throws {
        let author = TestFactory.feedPost(id: "author")
        let priorPin = TestFactory.feedPost(id: "prior-pin")
        var retriedPin = TestFactory.feedPost(id: "retried-pin")
        retriedPin.isPinned = true
        let fake = FakeFeedService()
        fake.feed = [author]
        fake.failPinnedPosts = true
        let model = makeModel(fake)
        var posts = [priorPin]
        var state = ProfilePartialLoadState()

        let loadedAuthorPosts = try await model.authorPosts(id: "actor")
        state.beginPinnedLoad()
        do {
            let loadedPins = try await model.pinnedPosts(id: "actor")
            state.finishPinned(.success(loadedPins), posts: &posts)
        } catch {
            state.finishPinned(.failure(error), posts: &posts)
        }

        XCTAssertEqual(loadedAuthorPosts.map(\.id), ["author"])
        XCTAssertEqual(posts.map(\.id), ["prior-pin"])
        XCTAssertNotNil(state.pinnedError)
        XCTAssertFalse(state.isPinnedLoading)

        fake.feed = [retriedPin]
        fake.failPinnedPosts = false
        state.beginPinnedLoad()
        let retriedPins = try await model.pinnedPosts(id: "actor")
        state.finishPinned(.success(retriedPins), posts: &posts)
        XCTAssertEqual(posts.map(\.id), ["retried-pin"])
        XCTAssertNil(state.pinnedError)
    }

    func testMessagingFetchFailuresPropagate() async {
        let fake = FakeFeedService()
        fake.failMessages = true
        fake.failConversations = true
        let model = makeModel(fake)

        do {
            _ = try await model.messages(
                in: "conversation",
                generation: model.mutationGeneration
            )
            XCTFail("message history failure must propagate")
        } catch {
            XCTAssertTrue(error is FakeFeedService.FakeError)
        }

        do {
            try await model.reloadConversations(generation: model.mutationGeneration)
            XCTFail("conversation refresh failure must propagate")
        } catch {
            XCTAssertTrue(error is FakeFeedService.FakeError)
        }
    }

    func testUnreadRefreshCanRetryAfterFailure() async {
        let fake = FakeFeedService()
        fake.failUnread = true
        let model = makeModel(fake)

        model.refreshUnreadCount()
        await waitUntil { fake.unreadCountCalls == 1 && model.unreadTask == nil }

        fake.failUnread = false
        fake.unread = 7
        model.refreshUnreadCount()
        await waitUntil { model.unreadCount == 7 }

        XCTAssertEqual(fake.unreadCountCalls, 2)
    }

    func testProfileLinkLookupFailureIsSurfacedWithoutNavigation() async throws {
        let fake = FakeFeedService()
        fake.failProfileForURL = true
        let model = makeModel(fake, target: .bluesky)
        let url = try XCTUnwrap(URL(string: "https://bsky.app/profile/did:plc:actor"))
        var routes: [FeedRoute] = []

        model.openLink(url) { routes.append($0) }
        await waitUntil { model.actionError != nil }

        XCTAssertTrue(routes.isEmpty)
    }
}
