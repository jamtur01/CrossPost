import Foundation
import SwiftUI

// Attachments can be constructed or mutated outside preparation, so outgoing bytes
// must be checked again at the submit boundary.
typealias UnreadablePostFinder = @Sendable (_ attachmentDataByPost: [[Data]]) -> Int?

enum OutgoingImageValidation {
    static func firstUnreadablePost(_ attachmentDataByPost: [[Data]]) -> Int? {
        for (postIndex, attachmentData) in attachmentDataByPost.enumerated() {
            for data in attachmentData {
                guard !Task.isCancelled else { return nil }
                if !ImageProcessor.canDecode(data) {
                    return postIndex
                }
            }
        }
        return nil
    }

    static func run(
        on attachmentDataByPost: [[Data]],
        using findUnreadablePost: @escaping UnreadablePostFinder
    ) async -> Int? {
        guard !attachmentDataByPost.allSatisfy(\.isEmpty) else { return nil }
        return await ImageAttaching.runDetached {
            findUnreadablePost(attachmentDataByPost)
        }
    }
}

@MainActor
@Observable
final class ComposeModel {
    var thread: [DraftPost] = [DraftPost()]
    var selectedTargets: Set<PostTarget> = [.mastodon, .bluesky]
    /// Mastodon visibility applied to every post in the thread at submit; Bluesky ignores it.
    var visibility: PostVisibility = .public
    var isPosting = false
    var blockedIssues: [ValidationIssue]?
    var errorMessage: String?

    private let coordinator = CrossPostCoordinator()
    private let store: AccountStore
    private let findUnreadablePost: UnreadablePostFinder
    private let makePosters: @MainActor ([PostTarget], AccountStore) async throws -> [Poster]
    /// What already landed on each target from a prior (possibly interrupted) submit:
    /// the published items (their native refs let a retry resume the thread) plus a
    /// per-post signature of each landed post, so an edit to an already-published post
    /// is detected and never silently re-sent.
    private struct LandedThread {
        let items: [PostedItem]
        let signatures: [PostSignature]
    }
    private var landedByTarget: [PostTarget: LandedThread] = [:]

    /// Why a target can't be (re)selected right now.
    enum LockReason: Equatable {
        case fullySent      // the whole current thread already landed
        case prefixEdited   // an already-published post was changed; can't resume safely
    }

    init(
        store: AccountStore,
        findUnreadablePost: @escaping UnreadablePostFinder =
            { OutgoingImageValidation.firstUnreadablePost($0) },
        makePosters: @escaping @MainActor ([PostTarget], AccountStore) async throws -> [Poster] =
            PosterFactory.makePosters
    ) {
        self.store = store
        self.findUnreadablePost = findUnreadablePost
        self.makePosters = makePosters
    }

    var canPost: Bool {
        !isPosting && !selectedTargets.isEmpty && thread.contains { !$0.isEmpty }
    }

    /// True when this target can't receive the current thread: either it's fully sent
    /// or its already-published prefix was edited. A target with intact landed posts
    /// and unsent posts below them is *resumable*, not locked.
    func isLocked(_ target: PostTarget) -> Bool { lockReason(target) != nil }

    func lockReason(_ target: PostTarget) -> LockReason? {
        guard let landed = landedByTarget[target] else { return nil }
        guard prefixIntact(landed) else { return .prefixEdited }
        return thread.count <= landed.items.count ? .fullySent : nil
    }

    /// Content identity of one post: the trimmed text plus attachment identities.
    /// A full value rather than a `Hasher` Int — a hash collision would silently
    /// defeat the edited-prefix lock and re-send or mis-thread a changed post.
    /// Visibility and alt text are deliberately excluded so changing them doesn't
    /// spuriously mark an intact prefix as edited.
    private struct PostSignature: Equatable {
        let text: String
        let attachmentIDs: [UUID]

        init(_ post: DraftPost) {
            text = post.text.trimmingCharacters(in: .whitespacesAndNewlines)
            attachmentIDs = post.attachments.map(\.id)
        }
    }

    /// Whether the current thread still begins with every landed post unchanged, so
    /// resuming would thread onto exactly what's live. A shorter thread (a landed
    /// post removed) or any changed prefix post fails this.
    private func prefixIntact(_ landed: LandedThread) -> Bool {
        guard thread.count >= landed.signatures.count else { return false }
        for (index, signature) in landed.signatures.enumerated()
        where PostSignature(thread[index]) != signature {
            return false
        }
        return true
    }

    func addPost() { thread.append(DraftPost()) }

    func removePost(at index: Int) {
        guard thread.count > 1, thread.indices.contains(index) else { return }
        thread.remove(at: index)
    }

    /// Applies a completed preparation to its original draft identity. A removed
    /// draft rejects the result without changing current errors or another post.
    @discardableResult
    func applyPreparedAttachments(_ result: ImageAttaching.PreparedResult,
                                  to draftID: UUID) -> Bool {
        guard let index = thread.firstIndex(where: { $0.id == draftID }) else {
            return false
        }
        let publication = ImageAttaching.publication(
            for: result,
            existingCount: thread[index].attachments.count
        )
        thread[index].attachments.append(contentsOf: publication.attachments)
        if let message = publication.errorMessage {
            errorMessage = message
        }
        return true
    }

    func toggle(_ target: PostTarget) {
        if selectedTargets.contains(target) {
            selectedTargets.remove(target)
        } else if let reason = lockReason(target) {
            errorMessage = lockMessage(target, reason)
        } else {
            selectedTargets.insert(target)
        }
    }

    private func lockMessage(_ target: PostTarget, _ reason: LockReason) -> String {
        switch reason {
        case .fullySent:
            return "Already posted to \(target.displayName). Add a new post to continue the thread."
        case .prefixEdited:
            return "Can't re-send to \(target.displayName): an already-posted post was changed. "
                + "Undo the change or clear the box."
        }
    }

    func submit() async {
        guard !Task.isCancelled, canPost else { return }
        isPosting = true
        blockedIssues = nil
        errorMessage = nil
        defer { isPosting = false }

        let targets = PostTarget.allCases.filter { selectedTargets.contains($0) }
        guard let outgoing = validatedOutgoing(for: targets) else { return }
        guard await attachmentsAreReadable(in: outgoing) else { return }

        do {
            let posters = try await makePosters(targets, store)
            guard !Task.isCancelled else { return }
            let outcome = await coordinator.publish(
                thread: outgoing,
                to: targets,
                using: posters,
                limits: store.limits,
                resuming: resumeItems(for: targets)
            )
            guard !Task.isCancelled else { return }
            switch outcome {
            case .blocked(let issues):
                blockedIssues = issues
            case .completed(let results):
                handleCompletion(results, published: outgoing)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.userMessage
        }
    }

    private func validatedOutgoing(for targets: [PostTarget]) -> [DraftPost]? {
        let edited = targets.filter {
            landedByTarget[$0].map { !prefixIntact($0) } ?? false
        }
        guard edited.isEmpty else {
            errorMessage = edited.map { lockMessage($0, .prefixEdited) }.joined(separator: "\n")
            return nil
        }

        let outgoing = thread.map { draft in
            var draft = draft
            draft.visibility = visibility
            return draft
        }
        let issues = PostValidator.validate(
            thread: outgoing,
            targets: targets,
            limits: store.limits
        )
        guard issues.isEmpty else {
            blockedIssues = issues
            return nil
        }
        return outgoing
    }

    private func attachmentsAreReadable(in outgoing: [DraftPost]) async -> Bool {
        let attachmentDataByPost = outgoing.map { post in
            post.attachments.map(\.imageData)
        }
        let badIndex = await OutgoingImageValidation.run(
            on: attachmentDataByPost,
            using: findUnreadablePost
        )
        guard !Task.isCancelled else { return false }
        guard let badIndex else { return true }
        errorMessage = "Post \(badIndex + 1) has an image that can't be read. "
            + "Remove it and try again."
        return false
    }

    private func resumeItems(for targets: [PostTarget]) -> [PostTarget: [PostedItem]] {
        var resuming: [PostTarget: [PostedItem]] = [:]
        for target in targets {
            guard let landed = landedByTarget[target], !landed.items.isEmpty else {
                continue
            }
            resuming[target] = landed.items
        }
        return resuming
    }

    /// Refresh the feed panels for platforms that received content, surface failures
    /// inline, and make retries safe: clear the box on a clean run; on a partial run
    /// keep the draft, record what landed per target (with refs for resume), deselect
    /// fully-sent targets, and keep partially-sent ones selected so pressing Post
    /// again publishes only the unsent remainder.
    /// Internal (not private) so the partial-failure reconciliation can be unit-tested.
    func handleCompletion(_ results: [PostResult], published: [DraftPost]? = nil) {
        // Sign the snapshot that was actually published, not the live thread: the
        // editor stays enabled during posting, so `thread` may have changed since.
        let published = published ?? thread
        var fullySent: [PostTarget] = []
        var anyLanded: [PostTarget] = []
        for result in results {
            let (items, complete) = landedItems(from: result)
            guard !items.isEmpty else { continue }
            anyLanded.append(result.target)
            let count = min(items.count, published.count)
            let signatures = (0..<count).map { PostSignature(published[$0]) }
            landedByTarget[result.target] = LandedThread(items: items, signatures: signatures)
            if complete { fullySent.append(result.target) }
        }

        if !anyLanded.isEmpty {
            NotificationCenter.default.post(name: .crossPostDidPost, object: nil,
                                            userInfo: [crossPostTargetsKey: Set(anyLanded)])
        }

        let failures = results.compactMap(failureMessage)
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")

        if failures.isEmpty {
            thread = [DraftPost()]      // clean run — clear the box and all locks
            landedByTarget = [:]
        } else {
            // Fully-sent targets have nothing left to send → deselect (locked).
            // Partially-sent targets stay selected so a retry resumes the remainder.
            selectedTargets.subtract(Set(fullySent))
        }
    }

    private func landedItems(from result: PostResult) -> ([PostedItem], Bool) {
        switch result.outcome {
        case .success(let posted): return (posted, true)
        case .partial(let posted, _, _): return (posted, false)
        case .failure: return ([], false)
        }
    }

    private func failureMessage(from result: PostResult) -> String? {
        switch result.outcome {
        case .success:
            return nil
        case .failure(let message):
            return "\(result.target.displayName): \(message)"
        case .partial(_, let failedIndex, let message):
            return "\(result.target.displayName): post \(failedIndex + 1) failed — \(message)"
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
