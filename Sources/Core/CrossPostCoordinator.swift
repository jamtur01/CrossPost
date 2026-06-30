import Foundation

struct CrossPostCoordinator: Sendable {
    init() {}

    /// Publish `thread` to each target. `resuming` carries the posts that already
    /// landed on a target from an interrupted attempt: only the unsent suffix is
    /// published, threaded onto the last landed post, so nothing is sent twice.
    func publish(thread: [DraftPost],
                        to targets: [PostTarget],
                        using posters: [Poster],
                        limits: TargetLimits,
                        resuming: [PostTarget: [PostedItem]] = [:]) async -> CrossPostOutcome {
        let issues = PostValidator.validate(thread: thread, targets: targets, limits: limits)
        guard issues.isEmpty else { return .blocked(issues: issues) }

        // The networks are independent, so post to them concurrently; results
        // keep the caller's target order.
        let results = await withTaskGroup(of: (Int, PostResult).self) { group in
            for (index, target) in targets.enumerated() {
                let poster = posters.first(where: { $0.target == target })
                let landed = resuming[target] ?? []
                group.addTask { (index, await Self.publish(thread: thread, to: target,
                                                           using: poster, landed: landed)) }
            }
            var indexed: [(Int, PostResult)] = []
            for await entry in group { indexed.append(entry) }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return .completed(results: results)
    }

    private static func publish(thread: [DraftPost], to target: PostTarget,
                                using poster: Poster?, landed: [PostedItem]) async -> PostResult {
        guard let poster else {
            return PostResult(target: target,
                              outcome: .failure(message: "No account configured for \(target.displayName)"))
        }
        // Skip the posts that already landed; resume the rest onto the last one.
        let suffix = Array(thread.dropFirst(landed.count))
        guard !suffix.isEmpty else { return PostResult(target: target, outcome: .success(posted: landed)) }
        // Resuming needs the last landed post's native ref to thread onto; without it
        // the suffix would post as a fresh, unthreaded thread. Refuse rather than do that.
        if !landed.isEmpty, landed.last?.ref == nil {
            return PostResult(target: target,
                              outcome: .partial(posted: landed, failedIndex: landed.count,
                                                message: "Couldn't resume the thread; please retry."))
        }
        do {
            let resumeRef = landed.last?.ref
            let posted = try await poster.post(thread: suffix, continuingFrom: resumeRef)
            return PostResult(target: target, outcome: .success(posted: landed + posted))
        } catch let e as ThreadPostError {
            // Index is absolute over the full thread, posted includes the resumed prefix.
            return PostResult(target: target,
                              outcome: .partial(posted: landed + e.posted,
                                                failedIndex: landed.count + e.failedIndex,
                                                message: e.underlying.userMessage))
        } catch {
            // A resume whose first new post fails keeps the landed prefix so a later
            // retry doesn't re-send it; a fresh attempt with nothing landed is a plain failure.
            if landed.isEmpty {
                return PostResult(target: target, outcome: .failure(message: error.userMessage))
            }
            return PostResult(target: target,
                              outcome: .partial(posted: landed, failedIndex: landed.count,
                                                message: error.userMessage))
        }
    }
}
