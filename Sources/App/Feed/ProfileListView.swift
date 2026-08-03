import SwiftUI

/// A scrollable list of accounts (followers or following), each row tappable to
/// open that profile.
struct ProfileListView: View {
    let panel: FeedPanelModel
    let ref: ProfileListRef
    let push: (FeedRoute) -> Void

    @State private var profiles: [Profile] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var loadToken = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        Divider().opacity(0.5)
                    }
                    ProfileRowView(profile: profile) {
                        push(.profile(profile.profileRef()))
                    }
                }
                listLoadFooter(loading: loading, loadError: loadError, isEmpty: profiles.isEmpty,
                               emptyState: ("No one here yet", "person.2")) {
                    loadToken += 1
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: loadToken) { await load() }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            let loaded: [Profile] = switch ref.kind {
            case .followers: try await panel.followers(of: ref.accountID)
            case .following: try await panel.following(of: ref.accountID)
            case .likedBy:
                if let post = ref.post {
                    try await panel.likedBy(post)
                } else {
                    []
                }
            case .repostedBy:
                if let post = ref.post {
                    try await panel.repostedBy(post)
                } else {
                    []
                }
            }
            guard !Task.isCancelled else { return }
            profiles = loaded
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.userMessage
        }
        loading = false
    }
}
