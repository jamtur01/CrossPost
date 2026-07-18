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
            if landed.isEmpty {
                return PostResult(target: target,
                                  outcome: .failure(message: "No account configured for \(target.displayName)"))
            }
            // The landed prefix must survive into the result: a plain failure would
            // discard it and a later retry would re-send the whole thread.
            let remaining = thread.count - landed.count
            return PostResult(target: target,
                              outcome: .partial(posted: landed, failedIndex: landed.count,
                                                message: "No account configured for \(target.displayName), "
                                                    + "but \(landed.count) of \(thread.count) posts from the "
                                                    + "interrupted attempt already landed there. Reconnect the "
                                                    + "account, then retry to post the remaining \(remaining) "
                                                    + "without re-sending."))
        }
        // Skip the posts that already landed; resume the rest onto the last one.
        let suffix = Array(thread.dropFirst(landed.count))
        guard !suffix.isEmpty else { return PostResult(target: target, outcome: .success(posted: landed)) }
        // Resuming needs the last landed post's native ref to thread onto; without it
        // the suffix would post as a fresh, unthreaded thread. Retrying can never
        // supply the missing ref, so tell the user exactly what landed instead of
        // suggesting a retry that cannot succeed.
        if !landed.isEmpty, landed.last?.ref == nil {
            let urls = landed.compactMap(\.url)
            let landedList = urls.isEmpty ? "" : " Landed so far: \(urls.joined(separator: ", "))."
            return PostResult(target: target,
                              outcome: .partial(posted: landed, failedIndex: landed.count,
                                                message: "The thread partially posted to \(target.displayName): "
                                                    + "\(landed.count) of \(thread.count) posts landed, but the last "
                                                    + "one's reference is missing, so the remaining \(suffix.count) "
                                                    + "can't be resumed automatically.\(landedList) "
                                                    + "Post the rest manually as replies."))
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
