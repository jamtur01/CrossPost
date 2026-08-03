import XCTest
@testable import CrossPost

final class MediaPlayersTests: XCTestCase {
    func testMotionRequiresEveryVisibilityPredicate() {
        let fullyVisible = MotionVisibilityState(
            rowIsVisible: true,
            windowIsVisible: true,
            windowIsOccluded: false,
            windowIsMinimized: false,
            applicationIsActive: true
        )
        let blockedStates = [
            MotionVisibilityState(
                rowIsVisible: false,
                windowIsVisible: true,
                windowIsOccluded: false,
                windowIsMinimized: false,
                applicationIsActive: true
            ),
            MotionVisibilityState(
                rowIsVisible: true,
                windowIsVisible: false,
                windowIsOccluded: false,
                windowIsMinimized: false,
                applicationIsActive: true
            ),
            MotionVisibilityState(
                rowIsVisible: true,
                windowIsVisible: true,
                windowIsOccluded: true,
                windowIsMinimized: false,
                applicationIsActive: true
            ),
            MotionVisibilityState(
                rowIsVisible: true,
                windowIsVisible: true,
                windowIsOccluded: false,
                windowIsMinimized: true,
                applicationIsActive: true
            ),
            MotionVisibilityState(
                rowIsVisible: true,
                windowIsVisible: true,
                windowIsOccluded: false,
                windowIsMinimized: false,
                applicationIsActive: false
            )
        ]

        XCTAssertTrue(fullyVisible.allowsMotion)
        XCTAssertTrue(blockedStates.allSatisfy { !$0.allowsMotion })
    }
}
