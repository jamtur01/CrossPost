import SwiftUI

/// A scrollable list of accounts (followers or following), each row tappable to
/// open that profile.
struct ProfileListView: View {
    let panel: FeedPanelModel
    let ref: ProfileListRef
    let push: (FeedRoute) -> Void

    @State private var profiles: [Profile] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { Divider().opacity(0.5) }
                    row(profile)
                }
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if profiles.isEmpty {
                    Text("No one here yet")
                        .font(Theme.meta).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            switch ref.kind {
            case .followers: profiles = await panel.followers(of: ref.accountID)
            case .following: profiles = await panel.following(of: ref.accountID)
            case .likedBy: if let post = ref.post { profiles = await panel.likedBy(post) }
            case .repostedBy: if let post = ref.post { profiles = await panel.repostedBy(post) }
            }
            loading = false
        }
    }

    private func row(_ profile: Profile) -> some View {
        Button {
            push(.profile(ProfileRef(id: profile.id, handle: profile.handle,
                                     name: profile.name, avatar: profile.avatarURL)))
        } label: {
            HStack(alignment: .top, spacing: Theme.gutter) {
                AsyncImage(url: profile.avatarURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.avatarRing, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(Theme.name).lineLimit(1)
                    Text(profile.handle).font(Theme.handle).foregroundStyle(.secondary).lineLimit(1)
                    if !profile.bio.characters.isEmpty {
                        Text(profile.bio).font(Theme.meta).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.rowPaddingH).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
