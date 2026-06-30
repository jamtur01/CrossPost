import SwiftUI

/// An account list row — avatar, display name, handle, and optional bio — used
/// by the people list and search results so they read identically.
struct ProfileRowView: View {
    let profile: Profile
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Theme.gutter) {
                AvatarView(url: profile.avatarURL, size: Theme.avatarSmall)

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
            .hoverHighlight()
        }
        .buttonStyle(.plain)
    }
}
