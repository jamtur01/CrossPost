import SwiftUI

extension ProfileView {
    func load() async {
        let token = loadToken
        loading = true
        loadError = nil
        postsLoadError = nil

        let resolved: Profile
        do {
            resolved = ref.isMe
                ? try await panel.myProfile()
                : try await panel.profile(id: ref.id)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, loadToken == token else { return }
            loadError = error.userMessage
            loading = false
            return
        }

        guard !Task.isCancelled, loadToken == token else { return }
        profile = resolved
        if !ref.isMe {
            relationshipLoadToken += 1
        }
        pinnedLoadToken += 1

        do {
            let loadedPosts = try await panel.authorPosts(id: resolved.id)
            guard !Task.isCancelled, loadToken == token else { return }
            list.posts = loadedPosts
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, loadToken == token else { return }
            postsLoadError = error.userMessage
        }
        loading = false
    }

    func loadRelationship() async {
        guard !ref.isMe, let id = profile?.id else { return }
        invalidateRelationshipAction()
        partialLoad.beginRelationshipLoad()
        do {
            let loaded = try await panel.relationship(with: id)
            guard !Task.isCancelled else { return }
            partialLoad.finishRelationship(.success(loaded))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            partialLoad.finishRelationship(.failure(error))
        }
    }

    func loadPinnedPosts() async {
        guard let id = profile?.id else { return }
        partialLoad.beginPinnedLoad()
        do {
            let loaded = try await panel.pinnedPosts(id: id)
            guard !Task.isCancelled else { return }
            partialLoad.finishPinned(.success(loaded), posts: &pinnedList.posts)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            partialLoad.finishPinned(.failure(error), posts: &pinnedList.posts)
        }
    }

    func partialErrorRow(
        _ section: String,
        message: String,
        retry: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(section).font(.callout.weight(.medium))
                Text(message).font(Theme.meta).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, 10)
    }

    /// The author's timeline minus any post already shown in the pinned section,
    /// so the same id is never rendered twice in one container.
    var feedRows: [FeedPost] {
        let pinnedIDs = Set(pinnedList.posts.map(\.id))
        return list.posts.filter { !pinnedIDs.contains($0.id) }
    }
}
