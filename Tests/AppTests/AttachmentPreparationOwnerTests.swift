import AppKit
import UniformTypeIdentifiers
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

    func testProviderBridgeCancellationCancelsTransferBeforeCallback() async {
        let provider = FakeAttachmentProvider<Data>()
        let task = Task {
            try await ImageAttaching.loadProviderValue { completion in
                provider.load(completion)
            }
        }
        await provider.waitUntilStarted()

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected provider load cancellation")
        } catch is CancellationError {
            XCTAssertTrue(provider.progress.isCancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        provider.complete(Data([0x01]))
    }

    func testProviderBridgeCallbackWinsLaterCancellation() async throws {
        let provider = FakeAttachmentProvider<Data>()
        let expected = Data([0x01])
        let task = Task {
            try await ImageAttaching.loadProviderValue { completion in
                provider.load(completion)
            }
        }
        await provider.waitUntilStarted()

        provider.complete(expected)
        let result = try await task.value
        task.cancel()

        XCTAssertEqual(result, expected)
        XCTAssertFalse(provider.progress.isCancelled)
    }

    func testProviderBridgeResumesOnlyOnceForDuplicateCallbacks() async throws {
        let provider = FakeAttachmentProvider<Data>()
        let task = Task {
            try await ImageAttaching.loadProviderValue { completion in
                provider.load(completion)
            }
        }
        await provider.waitUntilStarted()

        provider.complete(Data([0x01]))
        provider.complete(Data([0x02]))

        let result = try await task.value
        XCTAssertEqual(result, Data([0x01]))
    }

    func testProviderPreparationProducesAttachment() async {
        let provider = NSItemProvider()
        provider.suggestedName = "paste.png"
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(TestFactory.pngData(), nil)
            return Progress(totalUnitCount: 1)
        }
        let selection = ImageAttaching.selectProviders(
            [provider],
            remainingSlots: 1
        )

        let result = await ImageAttaching.prepare(selection)

        XCTAssertEqual(result?.attachments.count, 1)
        XCTAssertEqual(result?.failedNames, [])
        XCTAssertEqual(result?.unnamedFailureCount, 0)
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

private final class FakeAttachmentProvider<Value: Sendable>: @unchecked Sendable {
    typealias Completion = @Sendable (Value) -> Void

    let progress = Progress(totalUnitCount: 1)
    private let lock = NSLock()
    private var completion: Completion?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func load(_ completion: @escaping Completion) -> Progress {
        let waiters = lock.withLock {
            self.completion = completion
            defer { startWaiters.removeAll() }
            return startWaiters
        }
        for waiter in waiters {
            waiter.resume()
        }
        return progress
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let started = lock.withLock {
                guard completion == nil else { return true }
                startWaiters.append(continuation)
                return false
            }
            if started {
                continuation.resume()
            }
        }
    }

    func complete(_ value: Value) {
        let completion = lock.withLock { self.completion }
        completion?(value)
    }
}
