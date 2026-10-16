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

    /// The counter for `post`: each shown network's final text counted the way its
    /// server counts it, reporting the network with the least room left.
    func counter(for post: DraftPost) -> PostCounter {
        let targets = previewTarget.map { [$0] } ?? PostTarget.allCases.filter { selectedTargets.contains($0) }
        let counters: [PostCounter] = targets.compactMap { target in
            guard let limit = store.limits.maxGraphemes[target] else { return nil }
            let count = PostValidator.countedGraphemes(post.rendered(for: target).text, for: target)
            return PostCounter(count: count, limit: limit, label: target.displayName)
        }
        guard let tightest = counters.min(by: { $0.remaining < $1.remaining }) else {
            return PostCounter(count: PostValidator.graphemeCount(post.text), limit: TargetLimits.blueskyMax,
                               label: nil)
        }
        let tied = counters.filter { $0.remaining == tightest.remaining }.count > 1
        return tied ? PostCounter(count: tightest.count, limit: tightest.limit, label: "Both networks") : tightest
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

/// A post card's character counter: the count and limit of the network with the
/// least room left, and which network that is.
struct PostCounter: Equatable {
    let count: Int
    let limit: Int
    let label: String?

    var remaining: Int {
        limit - count
    }
}

extension MentionPairStore {
    static let application: MentionPairStore = {
        // Hosted tests launch the app UI too; it must never touch the real pairs file.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return MentionPairStore(url: URL.temporaryDirectory
                .appending(path: "CrossPost-tests-\(UUID())/mention-pairs.json"))
        }
        return MentionPairStore(url: URL.applicationSupportDirectory
            .appending(path: "CrossPost/mention-pairs.json"))
    }()
}
