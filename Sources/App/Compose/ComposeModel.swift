import Foundation
import SwiftUI

@MainActor
@Observable
final class ComposeModel {
    var thread: [DraftPost] = [DraftPost()]
    var selectedTargets: Set<PostTarget> = [.mastodon, .bluesky]
    var isPosting = false
    var blockedIssues: [ValidationIssue]?
    var errorMessage: String?

    private let coordinator = CrossPostCoordinator()
    private let store: AccountStore

    init(store: AccountStore) { self.store = store }

    var canPost: Bool {
        !isPosting && !selectedTargets.isEmpty && thread.contains { !$0.isEmpty }
    }

    func addPost() { thread.append(DraftPost()) }

    func removePost(at index: Int) {
        guard thread.count > 1, thread.indices.contains(index) else { return }
        thread.remove(at: index)
    }

    func toggle(_ target: PostTarget) {
        if selectedTargets.contains(target) { selectedTargets.remove(target) }
        else { selectedTargets.insert(target) }
    }

    func submit() async {
        isPosting = true
        blockedIssues = nil; errorMessage = nil
        defer { isPosting = false }

        let targets = PostTarget.allCases.filter { selectedTargets.contains($0) }

        // Validate up front so length/empty errors abort before any network connection.
        let issues = PostValidator.validate(thread: thread, targets: targets, limits: store.limits)
        guard issues.isEmpty else { blockedIssues = issues; return }

        do {
            let posters = try await PosterFactory.makePosters(for: targets, store: store)
            let outcome = await coordinator.publish(thread: thread, to: targets,
                                                    using: posters, limits: store.limits)
            switch outcome {
            case .blocked(let issues): blockedIssues = issues
            case .completed(let results): handleCompletion(results)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// On success, clear the box and tell the feed panels to refresh the posted-to
    /// platforms; surface any per-target failures inline (no results popup).
    private func handleCompletion(_ results: [PostResult]) {
        let succeeded = results.compactMap { result -> PostTarget? in
            if case .success = result.outcome { return result.target } else { return nil }
        }
        if !succeeded.isEmpty {
            NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                            userInfo: [crossPostTargetsKey: Set(succeeded)])
            thread = [DraftPost()]   // clear the posting box
        }
        let failures = results.compactMap { result -> String? in
            switch result.outcome {
            case .success: return nil
            case .failure(let message): return "\(result.target.displayName): \(message)"
            case .partial(_, let failedIndex, let message):
                return "\(result.target.displayName): post \(failedIndex + 1) failed — \(message)"
            }
        }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}

/// Posted to the listed targets after a successful cross-post, so feed panels refresh.
extension Notification.Name {
    static let crossPostDidPost = Notification.Name("crossPostDidPost")
}

/// userInfo key carrying a `Set<PostTarget>` of successfully-posted platforms.
let crossPostTargetsKey = "targets"
