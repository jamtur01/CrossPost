@testable import CrossPost
import XCTest

final class ProfileRelationshipTests: XCTestCase {
    func testFailedUnfollowRestoresExactZeroFollowerCount() {
        let mutation = ProfileFollowMutation(
            previousRelationship: AccountRelationship(isFollowing: true),
            previousFollowerCount: 0
        )

        XCTAssertFalse(mutation.target)
        XCTAssertEqual(mutation.optimisticFollowerCount, 0)
        XCTAssertEqual(mutation.restoredFollowerCount(current: 0), 0)
    }

    func testRollbackPreservesNewerFollowerCount() {
        let mutation = ProfileFollowMutation(
            previousRelationship: AccountRelationship(isFollowing: false),
            previousFollowerCount: 10
        )

        XCTAssertEqual(mutation.optimisticFollowerCount, 11)
        XCTAssertEqual(mutation.restoredFollowerCount(current: 12), 12)
    }

    func testFollowAnsweredWithPendingRequestTakesBackOptimisticCount() {
        let mutation = ProfileFollowMutation(
            previousRelationship: AccountRelationship(isFollowing: false),
            previousFollowerCount: 10
        )
        let pending = AccountRelationship(isFollowing: false, isRequested: true)

        XCTAssertEqual(mutation.settledFollowerCount(current: 11, server: pending), 10)
        XCTAssertEqual(mutation.settledFollowerCount(current: 11, server: AccountRelationship(isFollowing: true)), 11)
    }

    func testClickingPendingRequestWithdrawsItWithoutChangingCount() {
        let mutation = ProfileFollowMutation(
            previousRelationship: AccountRelationship(isFollowing: false, isRequested: true),
            previousFollowerCount: 10
        )

        XCTAssertFalse(mutation.target)
        XCTAssertFalse(mutation.optimisticRelationship.isRequested)
        XCTAssertEqual(mutation.optimisticFollowerCount, 10)
    }

    func testCancelledFollowRollbackRestoresRelationshipAndCount() {
        let mutation = ProfileFollowMutation(
            previousRelationship: AccountRelationship(isFollowing: false),
            previousFollowerCount: 10
        )

        let rollback = mutation.rollback(currentFollowerCount: 11)

        XCTAssertFalse(rollback.relationship.isFollowing)
        XCTAssertEqual(rollback.followerCount, 10)
    }
}
