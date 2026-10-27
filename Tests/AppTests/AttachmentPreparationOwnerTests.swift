import AppKit
@testable import CrossPost
import UniformTypeIdentifiers
import XCTest

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

    func testAddingPostKeepsFirstDraftPreparationOwnedByThatDraft() async {
        let model = ComposeModel(store: AccountStore())
        let owner = AttachmentPreparationOwner()
        let gate = TestGate()
        let observedCancellation = PreparationFlag()
        let firstDraftID = model.thread[0].id
        let attachment = Attachment(imageData: TestFactory.pngData())

        let task = owner.start(
            operation: {
                await gate.wait()
                await observedCancellation.set(Task.isCancelled)
                return ImageAttaching.PreparedResult(attachments: [attachment])
            },
            onPrepared: { result in
                _ = model.applyPreparedAttachments(result, to: firstDraftID)
            }
        )
        await waitUntil { gate.arrivals == 1 }

        model.addPost()
        gate.open()
        await task.value

        XCTAssertFalse(observedCancellation.value)
        XCTAssertEqual(model.thread[0].id, firstDraftID)
        XCTAssertEqual(model.thread[0].attachments, [attachment])
    }

    func testBackgroundWorkerReceivesOuterCancellation() async {
        let gate = TestGate()
        let observedCancellation = PreparationFlag()
        let task = Task {
            await ImageAttaching.runInBackground {
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

    func testWorkerStartsCancelledWhenParentIsAlreadyCancelled() async {
        var missedCancellations = 0
        for _ in 0 ..< 1000 {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await ImageAttaching.runInBackground { Task.isCancelled }
            }
            let wasCancelled = await task.value
            if !wasCancelled {
                missedCancellations += 1
            }
        }
        XCTAssertEqual(missedCancellations, 0)
    }

    func testProviderBridgeCancellationCancelsTransferBeforeCallback() async {
        let provider = FakeAttachmentProvider<Data>()
        let task = Task.detached {
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
        let task = Task.detached {
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
        let task = Task.detached {
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

    /// Dropping or pasting into the text editor goes through this, so each kind of
    /// pasteboard must become an attachment, or be left to the editor as text.
    func testPasteboardImagesBecomeAttachmentsAndTextStaysText() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("crosspost-test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        func attachments(_ write: () -> Void) async -> Int? {
            pasteboard.clearContents()
            write()
            guard let providers = ImageAttaching.imageProviders(on: pasteboard) else { return nil }
            let selection = ImageAttaching.selectProviders(providers, remainingSlots: 4)
            return await ImageAttaching.prepare(selection)?.attachments.count
        }
        let imageFile = URL.temporaryDirectory.appending(path: "drop-\(UUID()).png")
        let textFile = URL.temporaryDirectory.appending(path: "drop-\(UUID()).txt")
        try TestFactory.pngData().write(to: imageFile)
        try Data("hi".utf8).write(to: textFile)
        defer {
            try? FileManager.default.removeItem(at: imageFile)
            try? FileManager.default.removeItem(at: textFile)
        }

        let fromFile = await attachments { pasteboard.writeObjects([imageFile as NSURL]) }
        XCTAssertEqual(fromFile, 1, "a dropped image file")
        let fromData = await attachments { pasteboard.setData(TestFactory.pngData(), forType: .png) }
        XCTAssertEqual(fromData, 1, "copied image data")
        let fromText = await attachments { pasteboard.setString("hello", forType: .string) }
        XCTAssertNil(fromText, "plain text")
        let fromRichText = await attachments {
            pasteboard.setString("hello", forType: .string)
            pasteboard.setData(TestFactory.pngData(), forType: .png)
        }
        XCTAssertNil(fromRichText, "text that carries a picture")
        let fromOtherFile = await attachments { pasteboard.writeObjects([textFile as NSURL]) }
        XCTAssertNil(fromOtherFile, "a file that isn't an image")
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

private final class FakeAttachmentProvider<Value: Sendable>: @unchecked Sendable { // state behind `lock`
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
