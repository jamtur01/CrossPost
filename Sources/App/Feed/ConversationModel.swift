import Foundation
import Observation

@MainActor
@Observable
final class ConversationModel {
    let conversation: Conversation

    private(set) var messages: [DirectMessage] = []
    var draft = ""
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var loadError: String?
    private(set) var errorMessage: String?

    @ObservationIgnored private let panel: FeedPanelModel
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration: UInt = 0
    @ObservationIgnored private var sendGeneration: UInt = 0

    init(panel: FeedPanelModel, conversation: Conversation) {
        self.panel = panel
        self.conversation = conversation
    }

    func start() {
        guard loadTask == nil else { return }
        reload()
    }

    func reload() {
        let generation = beginHistoryLoad()
        loadError = nil
        if messages.isEmpty {
            isLoading = true
        }
        let panelGeneration = panel.mutationGeneration
        loadTask = Task { [weak self] in
            await self?.load(
                generation: generation,
                panelGeneration: panelGeneration
            )
        }
    }

    func send() {
        let submittedDraft = draft
        let text = submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sendTask == nil else { return }
        isSending = true
        errorMessage = nil
        sendGeneration += 1
        let generation = sendGeneration
        let panelGeneration = panel.mutationGeneration
        sendTask = Task { [weak self] in
            await self?.send(
                text,
                submittedDraft: submittedDraft,
                generation: generation,
                panelGeneration: panelGeneration
            )
        }
    }

    func stop() {
        loadGeneration += 1
        sendGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        sendTask?.cancel()
        sendTask = nil
        isLoading = false
        isSending = false
    }

    private func load(generation: UInt, panelGeneration: UInt) async {
        do {
            let fetched = try await panel.messages(
                in: conversation.id,
                generation: panelGeneration
            )
            guard !Task.isCancelled, loadGeneration == generation else { return }
            messages = fetched
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, loadGeneration == generation else { return }
            loadError = error.userMessage
        }
        guard loadGeneration == generation else { return }
        loadTask = nil
        isLoading = false
    }

    private func send(
        _ text: String,
        submittedDraft: String,
        generation: UInt,
        panelGeneration: UInt
    ) async {
        do {
            try await panel.sendMessage(
                text,
                to: conversation.id,
                generation: panelGeneration
            )
        } catch is CancellationError {
            finishSend(generation: generation)
            return
        } catch {
            guard sendGeneration == generation else { return }
            errorMessage = error.userMessage
            finishSend(generation: generation)
            return
        }

        guard sendGeneration == generation, !Task.isCancelled else { return }
        if draft == submittedDraft {
            draft = ""
        }
        let historyGeneration = beginHistoryLoad()
        await reloadAfterConfirmedSend(
            generation: generation,
            historyGeneration: historyGeneration,
            panelGeneration: panelGeneration
        )
        finishSend(generation: generation)
    }

    private func reloadAfterConfirmedSend(
        generation: UInt,
        historyGeneration: UInt,
        panelGeneration: UInt
    ) async {
        do {
            let fetched = try await panel.messages(
                in: conversation.id,
                generation: panelGeneration
            )
            guard sendGeneration == generation,
                  loadGeneration == historyGeneration else { return }
            messages = fetched
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            guard sendGeneration == generation,
                  loadGeneration == historyGeneration else { return }
            loadError = error.userMessage
        }

        if loadGeneration == historyGeneration {
            isLoading = false
        }

        do {
            try await panel.reloadConversations(generation: panelGeneration)
        } catch is CancellationError {
            return
        } catch {
            guard sendGeneration == generation else { return }
            errorMessage = "Message sent, but conversations couldn't refresh. \(error.userMessage)"
        }
    }

    private func beginHistoryLoad() -> UInt {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        return loadGeneration
    }

    private func finishSend(generation: UInt) {
        guard sendGeneration == generation else { return }
        sendTask = nil
        isSending = false
    }
}
