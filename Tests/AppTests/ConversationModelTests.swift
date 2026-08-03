@testable import CrossPost
import XCTest

@MainActor
final class ConversationModelTests: FeedPanelTestCase {
    func testSupersededHistoryLoadCannotOverwriteNewerMessages() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        fake.messagesToReturn = [message(id: "old")]
        fake.messagesDelay = {
            if fake.messagesCalls == 1 {
                await gate.wait()
            }
        }
        let model = makeConversationModel(fake)

        model.start()
        await waitUntil { gate.arrivals == 1 }
        fake.messagesToReturn = [message(id: "new")]
        model.reload()
        await waitUntil { model.messages.map(\.id) == ["new"] }

        gate.open()
        await Task.yield()

        XCTAssertEqual(model.messages.map(\.id), ["new"])
        XCTAssertNil(model.loadError)
    }

    func testPostSendHistoryReloadSupersedesInitialLoad() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        fake.messagesToReturn = [message(id: "old")]
        fake.messagesDelay = {
            if fake.messagesCalls == 1 {
                await gate.wait()
            }
        }
        let model = makeConversationModel(fake)

        model.start()
        await waitUntil { gate.arrivals == 1 }
        fake.messagesToReturn = [message(id: "new")]
        model.draft = "hello"
        model.send()
        await waitUntil { model.messages.map(\.id) == ["new"] }

        gate.open()
        await waitUntil { fake.messagesCompletions == 2 }

        XCTAssertEqual(model.messages.map(\.id), ["new"])
        XCTAssertNil(model.loadError)
    }

    func testCredentialRestartCancelsSendCompletionAndHistoryReload() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        let panel = makeModel(fake)
        let model = ConversationModel(panel: panel, conversation: conversation())
        fake.sendMessageDelay = { await gate.wait() }
        model.draft = "hello"

        model.send()
        await waitUntil { fake.sentMessages == ["hello"] }
        panel.restartAfterCredentialsChange()
        model.stop()
        gate.open()
        await Task.yield()

        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(fake.messagesCalls, 0)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isSending)
    }

    func testSendFailureRestoresDraftAndShowsError() async {
        let fake = FakeFeedService()
        fake.failSendMessage = true
        let model = makeConversationModel(fake)
        model.draft = "keep me"

        model.send()
        await waitUntil { !model.isSending }

        XCTAssertEqual(model.draft, "keep me")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(fake.messagesCalls, 0)
    }

    func testSendFailureDoesNotOverwriteNewerDraft() async {
        let fake = FakeFeedService()
        let gate = TestGate()
        fake.failSendMessage = true
        fake.sendMessageDelay = { await gate.wait() }
        let model = makeConversationModel(fake)
        model.draft = "failed message"

        model.send()
        await waitUntil { fake.sentMessages == ["failed message"] }
        model.draft = "next message"
        gate.open()
        await waitUntil { !model.isSending }

        XCTAssertEqual(model.draft, "next message")
        XCTAssertNotNil(model.errorMessage)
    }

    func testSuccessfulSendClearsWhitespacePaddedDraft() async {
        let fake = FakeFeedService()
        let model = makeConversationModel(fake)
        model.draft = "  hello  "

        model.send()
        await waitUntil { !model.isSending }

        XCTAssertEqual(fake.sentMessages, ["hello"])
        XCTAssertTrue(model.draft.isEmpty)
    }

    func testCanceledSendCannotClearReplacementSendState() async {
        let fake = FakeFeedService()
        let firstGate = TestGate()
        let secondGate = TestGate()
        fake.sendMessageDelay = {
            if fake.sentMessages.count == 1 {
                await firstGate.wait()
            } else {
                await secondGate.wait()
            }
        }
        let model = makeConversationModel(fake)
        model.draft = "first"
        model.send()
        await waitUntil { firstGate.arrivals == 1 }

        model.stop()
        model.draft = "second"
        model.send()
        await waitUntil { secondGate.arrivals == 1 }

        firstGate.open()
        await waitUntil { fake.sendMessageCompletions == 1 }
        await Task.yield()
        XCTAssertTrue(model.isSending)

        secondGate.open()
        await waitUntil { !model.isSending }
        XCTAssertEqual(fake.sentMessages, ["first", "second"])
    }

    private func makeConversationModel(_ fake: FakeFeedService) -> ConversationModel {
        ConversationModel(panel: makeModel(fake), conversation: conversation())
    }

    private func conversation() -> Conversation {
        Conversation(
            id: "conversation",
            otherName: "Other",
            otherHandle: "@other",
            otherID: "other",
            otherAvatarURL: nil,
            lastMessage: nil,
            lastDate: nil,
            unreadCount: 0
        )
    }

    private func message(id: String) -> DirectMessage {
        DirectMessage(id: id, text: id, date: Date(), isFromMe: false)
    }
}
