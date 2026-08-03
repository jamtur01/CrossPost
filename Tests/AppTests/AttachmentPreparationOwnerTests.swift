import XCTest
@testable import CrossPost

@MainActor
final class AttachmentPreparationOwnerTests: XCTestCase {
    func testReplacementRejectsFirstPreparationAfterItReturns() async {
        let owner = AttachmentPreparationOwner()
        let firstGate = TestGate()
        let secondGate = TestGate()
        let firstObservedCancellation = PreparationFlag()
        let first = Attachment(imageData: Data([0x01]))
        let second = Attachment(imageData: Data([0x02]))
        var applied: [UUID] = []

        let firstTask = owner.start(
            operation: {
                await firstGate.wait()
                await firstObservedCancellation.set(Task.isCancelled)
                return ImageAttaching.PreparedResult(attachments: [first])
            },
            onPrepared: { applied.append(contentsOf: $0.attachments.map(\.id)) }
        )
        await waitUntil { firstGate.arrivals == 1 }

        let secondTask = owner.start(
            operation: {
                await secondGate.wait()
                return ImageAttaching.PreparedResult(attachments: [second])
            },
            onPrepared: { applied.append(contentsOf: $0.attachments.map(\.id)) }
        )
        await waitUntil { secondGate.arrivals == 1 }
        secondGate.open()
        await secondTask.value

        firstGate.open()
        await firstTask.value

        XCTAssertEqual(applied, [second.id])
        XCTAssertTrue(firstObservedCancellation.value)
    }

    func testCancelRejectsLateReplyAttachmentsAndError() async {
        let owner = AttachmentPreparationOwner()
        let gate = TestGate()
        let observedCancellation = PreparationFlag()
        let model = ReplyModel(
            post: TestFactory.feedPost(target: .bluesky),
            store: AccountStore()
        )
        let attachment = Attachment(imageData: TestFactory.pngData())

        let task = owner.start(
            operation: {
                await gate.wait()
                await observedCancellation.set(Task.isCancelled)
                return ImageAttaching.PreparedResult(
                    attachments: [attachment],
                    failedNames: ["late.png"],
                    exceededLimit: true
                )
            },
            onPrepared: model.applyPreparedAttachments
        )
        await waitUntil { gate.arrivals == 1 }

        owner.cancel()
        gate.open()
        await task.value

        XCTAssertTrue(model.attachments.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(observedCancellation.value)
    }

    func testDetachedWorkerReceivesOuterCancellation() async {
        let gate = TestGate()
        let observedCancellation = PreparationFlag()
        let task = Task {
            await ImageAttaching.runDetached {
                await gate.wait()
                await observedCancellation.set(Task.isCancelled)
            }
        }
        await waitUntil { gate.arrivals == 1 }

        task.cancel()
        gate.open()
        await task.value

        XCTAssertTrue(observedCancellation.value)
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool,
                           timeout: TimeInterval = 2,
                           file: StaticString = #filePath,
                           line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            await Task.yield()
        }
    }
}

@MainActor
private final class PreparationFlag {
    private(set) var value = false

    func set(_ value: Bool = true) {
        self.value = value
    }
}
