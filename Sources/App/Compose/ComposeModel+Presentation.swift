import Foundation

extension ComposeModel {
    func scheduleCompletionDismissal() {
        completionDismissTask?.cancel()
        completionDismissTask = nil
        guard completionMessage != nil else { return }
        completionDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return // Dismissal was cancelled by a new draft or submission.
            }
            guard !Task.isCancelled else { return }
            self?.completionMessage = nil
        }
    }

    /// The counters for `post`: each shown network's final text counted the way its
    /// server counts it, against that network's own limit, in display order. With no
    /// network selected, the plain text is counted against the strictest limit.
    func counters(for post: DraftPost) -> [PostCounter] {
        let targets = previewTarget.map { [$0] } ?? PostTarget.allCases.filter { selectedTargets.contains($0) }
        let counters: [PostCounter] = targets.compactMap { target in
            guard let limit = store.limits.maxGraphemes[target] else { return nil }
            let count = PostValidator.countedGraphemes(post.rendered(for: target).text, for: target)
            return PostCounter(count: count, limit: limit, label: target.displayName)
        }
        guard counters.isEmpty else { return counters }
        return [PostCounter(count: PostValidator.graphemeCount(post.text), limit: TargetLimits.blueskyMax, label: nil)]
    }

    /// The editor's placeholder, naming the networks the draft goes to.
    var editorPlaceholder: String {
        switch PostTarget.allCases.filter({ selectedTargets.contains($0) }) {
        case [.mastodon, .bluesky]: "Write once for Mastodon and Bluesky"
        case let targets where targets.count == 1: "Write for \(targets[0].displayName)"
        default: "Write a post"
        }
    }

    /// Nothing written and nothing sending: the composer can show its history.
    var isIdle: Bool {
        !isPosting && thread.allSatisfy(\.isEmpty)
    }

    /// Networks mention search uses: selected, with an account configured.
    var mentionTargets: [PostTarget] {
        PostTarget.allCases.filter { target in
            selectedTargets.contains(target) && (target == .mastodon ? store.hasMastodon : store.hasBluesky)
        }
    }

    func searchMentions(_ query: String) async -> MentionDirectory.Results {
        await mentionDirectory.search(query, on: mentionTargets)
    }

    /// The autocomplete state for one post card, created on first use.
    func mentionCompletion(for draftID: UUID) -> MentionCompletion {
        if let existing = mentionCompletions[draftID] {
            return existing
        }
        let completion = MentionCompletion { [weak self] query in
            await self?.searchMentions(query) ?? MentionDirectory.Results(people: [], failed: [])
        }
        mentionCompletions[draftID] = completion
        return completion
    }

    /// Fills the requested network's account on the mention being paired and
    /// remembers the pair so later searches merge the two accounts.
    func completePairing(with chosen: MentionPerson) {
        guard let request = pairing else { return }
        pairing = nil
        guard let postIndex = thread.firstIndex(where: { $0.id == request.draftID }),
              let spanIndex = thread[postIndex].mentions.firstIndex(of: request.span) else { return }
        var person = request.span.person
        switch request.target {
        case .mastodon: person.mastodonAcct = chosen.mastodonAcct
        case .bluesky: person.blueskyHandle = chosen.blueskyHandle
        }
        thread[postIndex].mentions[spanIndex].person = person
        guard let acct = person.mastodonAcct, let handle = person.blueskyHandle else { return }
        do {
            try mentionDirectory.pairStore.save(MentionPair(mastodonAcct: acct, blueskyHandle: handle))
        } catch {
            errorMessage = "Couldn't save the account pairing: \(error.userMessage)"
        }
    }

    var submissionLabel: String {
        if isPosting {
            return "Posting…"
        }
        let failed = lastResults.filter { result in
            guard selectedTargets.contains(result.target) else { return false }
            switch result.outcome {
            case .success: return false
            case .failure, .partial: return true
            }
        }
        if !failed.isEmpty {
            return selectedTargets.count == 1 ? "Retry \(failed[0].target.displayName)" : "Retry posts"
        }
        return landedByTarget.isEmpty ? "Post" : "Continue thread"
    }

    func publicationStatus(for target: PostTarget) -> String? {
        if pendingTargets.contains(target) {
            return "\(target.displayName): \(isPosting ? "Posting…" : "Interrupted; check your profile")"
        }
        if let result = lastResults.last(where: { $0.target == target }) {
            switch result.outcome {
            case let .success(items):
                return "\(target.displayName): \(items.count) posted"
            case let .partial(items, _, _):
                return "\(target.displayName): \(items.count) posted; remaining posts failed"
            case .failure:
                return "\(target.displayName): Failed"
            }
        }
        if let landed = landedByTarget[target] {
            return "\(target.displayName): \(landed.items.count) already posted"
        }
        return nil
    }
}

/// One network's character count for a post card, against that network's limit.
struct PostCounter: Equatable {
    let count: Int
    let limit: Int
    /// The network's name; nil when no network is selected.
    let label: String?
}

extension MentionPairStore {
    static let application: MentionPairStore = {
        // Hosted tests launch the app UI too; it must never touch the real pairs file.
        if ProcessInfo.processInfo.isRunningTests {
            return MentionPairStore(url: URL.temporaryDirectory
                .appending(path: "CrossPost-tests-\(UUID())/mention-pairs.json"))
        }
        return MentionPairStore(url: URL.applicationSupportDirectory
            .appending(path: "CrossPost/mention-pairs.json"))
    }()
}
