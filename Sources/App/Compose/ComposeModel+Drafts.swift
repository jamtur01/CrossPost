import Foundation

extension ComposeModel {
    private var savedDraft: SavedComposeDraft {
        SavedComposeDraft(
            thread: thread, selectedTargets: selectedTargets, visibility: visibility,
            landed: landedByTarget, pendingTargets: pendingTargets
        )
    }

    func accountKey(for target: PostTarget) -> String {
        switch target {
        case .mastodon:
            "\(store.mastodonBaseURL?.absoluteString ?? "")|\(store.mastodonUsername.lowercased())"
        case .bluesky:
            store.blueskyHandle.lowercased()
        }
    }

    /// In-memory only; secrets fence account changes across awaits and are never archived.
    func credentialSnapshot(for targets: [PostTarget]) -> [PostTarget: [String]] {
        var snapshot: [PostTarget: [String]] = [:]
        for target in targets {
            switch target {
            case .mastodon:
                snapshot[target] = [store.mastodonBaseURL?.absoluteString ?? "", store.mastodonToken]
            case .bluesky:
                snapshot[target] = [store.blueskyHandle.lowercased(), store.blueskyAppPassword]
            }
        }
        return snapshot
    }

    func restoreDraft() {
        do {
            if let saved = try draftStore?.load() {
                guard !saved.thread.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                thread = saved.thread
                selectedTargets = saved.selectedTargets
                visibility = saved.visibility
                landedByTarget = saved.landed
                pendingTargets = saved.pendingTargets
                if !pendingTargets.isEmpty {
                    errorMessage = "Posting was interrupted. Check your profiles before starting a new draft."
                }
            }
            restoringDraft = false
        } catch {
            // Preserve an unreadable archive until the user explicitly starts a new draft.
            draftError = "Couldn't restore your draft: \(error.userMessage) "
                + "The saved file has been kept. Copy it before starting a new draft."
        }
    }

    func scheduleDraftSave() {
        guard !restoringDraft, let draftStore else { return }
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                try await draftStore.save(savedDraft)
                guard !Task.isCancelled else { return }
                draftError = nil
            } catch is CancellationError {
                return
            } catch {
                self?.draftError = "Couldn't save your draft: \(error.userMessage)"
            }
        }
    }

    @discardableResult
    func flushDraft() -> Bool {
        guard !restoringDraft else { return false }
        draftSaveTask?.cancel()
        draftSaveTask = nil
        do {
            try draftStore?.flush(savedDraft)
            draftError = nil
            return true
        } catch {
            draftError = "Couldn't save your draft: \(error.userMessage)"
            return false
        }
    }

    func startNewDraft() {
        guard !isPosting else { return }
        restoringDraft = false
        landedByTarget = [:]
        pendingTargets = []
        publishingAccounts = [:]
        selectedTargets = Set(PostTarget.allCases)
        visibility = .public
        thread = [DraftPost()]
        blockedIssues = nil
        errorMessage = nil
        completionMessage = nil
        lastResults = []
        _ = flushDraft()
    }
}
