@testable import CrossPost
import XCTest

final class PagedTests: XCTestCase {
    private enum Failure: Error { case unavailable }

    func testPublishesEachPageBeforeRequestingTheNext() async throws {
        var published: [[Int]] = []
        let result = try await paged(target: 3, maxPages: 3, onPage: { published.append($0) }, { (cursor: Int?) in
            let page = cursor ?? 0
            XCTAssertEqual(published.count, page)
            return ([page], page + 1)
        })
        XCTAssertEqual(published, [[0], [0, 1], [0, 1, 2]])
        XCTAssertEqual(result, [0, 1, 2])
    }

    func testLaterFailureDoesNotWithholdTheFirstPage() async {
        var published: [Int] = []
        do {
            _ = try await paged(target: 3, maxPages: 3, onPage: { published = $0 }, { (cursor: Int?) in
                if cursor != nil {
                    throw Failure.unavailable
                }
                return ([1], 1)
            })
            XCTFail("Expected the second page to fail")
        } catch {
            XCTAssertEqual(published, [1])
        }
    }

    func testCanceledPageIsNotPublishedOrFollowed() async {
        let task = Task {
            var calls = 0
            do {
                _ = try await paged(target: 3, maxPages: 3, onPage: { (_: [Int]) in
                    XCTFail("Canceled content must not be published")
                }, { (cursor: Int?) in
                    calls += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                    return ([1], (cursor ?? 0) + 1)
                })
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
            XCTAssertEqual(calls, 1)
        }
        await task.value
    }
}
