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
