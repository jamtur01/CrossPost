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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { Divider().opacity(0.5) }
                    ProfileRowView(profile: profile) {
                        push(.profile(ProfileRef(id: profile.id, handle: profile.handle,
                                                 name: profile.name, avatar: profile.avatarURL)))
                    }
                }
                listLoadFooter(loading: loading, error: loadError, isEmpty: profiles.isEmpty,
                               emptyText: "No one here yet", emptyImage: "person.2") {
                    Task { await load() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task { await load() }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            switch ref.kind {
            case .followers: profiles = try await panel.followers(of: ref.accountID)
            case .following: profiles = try await panel.following(of: ref.accountID)
            case .likedBy: if let post = ref.post { profiles = try await panel.likedBy(post) }
            case .repostedBy: if let post = ref.post { profiles = try await panel.repostedBy(post) }
            }
        } catch {
            loadError = error.userMessage
        }
        loading = false
    }
}
