import Foundation
import SwiftUI

@MainActor
@Observable
final class ComposeModel {
    var thread: [DraftPost] = [DraftPost()]
    var selectedTargets: Set<PostTarget> = [.mastodon, .bluesky]
    var isPosting = false
    var results: [PostResult]?
    var blockedIssues: [ValidationIssue]?
    var errorMessage: String?

    private let coordinator = CrosspostCoordinator()
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
        results = nil; blockedIssues = nil; errorMessage = nil
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
            case .completed(let results): self.results = results
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
