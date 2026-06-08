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
    private let makePosters: @MainActor ([PostTarget], AccountStore) async throws -> [Poster]

    /// The content signature each target last received, so re-pressing Post can't
    /// duplicate an already-published thread. Editing the thread changes the
    /// signature, which releases the lock automatically.
    private var postedSignatures: [PostTarget: Int] = [:]

    init(store: AccountStore,
         makePosters: @escaping @MainActor ([PostTarget], AccountStore) async throws -> [Poster]
             = PosterFactory.makePosters) {
        self.store = store
        self.makePosters = makePosters
    }

    var canPost: Bool {
        !isPosting && !selectedTargets.isEmpty && thread.contains { !$0.isEmpty }
    }

    /// True when this target already received the current thread content; selecting
    /// it would duplicate that post.
    func isLocked(_ target: PostTarget) -> Bool {
        postedSignatures[target] == contentSignature
    }

    private var contentSignature: Int {
        var hasher = Hasher()
        for post in thread {
            hasher.combine(post.text.trimmingCharacters(in: .whitespacesAndNewlines))
            hasher.combine(post.attachments.map(\.id))
        }
        return hasher.finalize()
    }

    func addPost() { thread.append(DraftPost()) }

    func removePost(at index: Int) {
        guard thread.count > 1, thread.indices.contains(index) else { return }
        thread.remove(at: index)
    }

    func toggle(_ target: PostTarget) {
        if selectedTargets.contains(target) {
            selectedTargets.remove(target)
        } else if isLocked(target) {
            errorMessage = "Already posted to \(target.displayName). Edit a post to send again."
        } else {
            selectedTargets.insert(target)
        }
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
            let posters = try await makePosters(targets, store)
            let outcome = await coordinator.publish(thread: thread, to: targets,
                                                    using: posters, limits: store.limits)
            switch outcome {
            case .blocked(let issues): blockedIssues = issues
            case .completed(let results): handleCompletion(results)
            }
        } catch {
            errorMessage = error.userMessage
        }
    }

    /// Refresh the feed panels for platforms that received content, surface any
    /// failures inline, and make retries safe: clear the box on a clean run, and on
    /// a partial run keep the draft but de-select every target that already received
    /// content so pressing Post again can't duplicate what already landed.
    /// Internal (not private) so the partial-failure reconciliation can be unit-tested.
    func handleCompletion(_ results: [PostResult]) {
        // Targets that received any content — fully (.success) or partly (.partial
        // with at least one landed post). A single-post failure reports `.partial`
        // with no landed posts, so it correctly stays eligible for retry.
        let landed = results.filter { result in
            switch result.outcome {
            case .success: return true
            case .partial(let posted, _, _): return !posted.isEmpty
            case .failure: return false
            }
        }.map(\.target)

        if !landed.isEmpty {
            // Lock each landed target against re-posting this exact content.
            let signature = contentSignature
            for target in landed { postedSignatures[target] = signature }
            NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                            userInfo: [crossPostTargetsKey: Set(landed)])
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

        if failures.isEmpty {
            thread = [DraftPost()]                 // clean run — clear the box
        } else {
            selectedTargets.subtract(Set(landed))  // partial — don't re-post what landed
        }
    }
}

/// Posted to the listed targets after a successful cross-post or reply, so feed panels refresh.
extension Notification.Name {
    static let crossPostDidPost = Notification.Name("crossPostDidPost")
    /// Posted when credentials for the listed targets are saved in Settings.
    static let crossPostCredentialsChanged = Notification.Name("crossPostCredentialsChanged")
}

/// userInfo key carrying a `Set<PostTarget>` of affected platforms.
let crossPostTargetsKey = "targets"
