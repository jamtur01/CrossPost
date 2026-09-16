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

    var characterLimit: Int {
        selectedTargets.compactMap { store.limits.maxGraphemes[$0] }.min() ?? TargetLimits.blueskyMax
    }

    var limitingNetwork: String? {
        let limiting = PostTarget.allCases.filter {
            selectedTargets.contains($0) && store.limits.maxGraphemes[$0] == characterLimit
        }
        return limiting.count == 2 ? "Both networks" : limiting.first?.displayName
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
