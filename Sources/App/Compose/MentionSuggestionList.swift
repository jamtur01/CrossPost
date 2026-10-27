import SwiftUI

/// One person in mention suggestions: avatar, name, each network's handle, and
/// a badge per network they're on.
struct MentionPersonRow: View {
    let person: MentionPerson
    var selected = false

    var body: some View {
        HStack(spacing: 9) {
            AvatarView(url: person.avatarURL, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.displayName.isEmpty ? person.visibleText : person.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(handles)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(networks) { target in
                    Image(systemName: target.glyph)
                        .font(.system(size: 12))
                        .foregroundStyle(target.accent)
                        .help(target.displayName)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var networks: [PostTarget] {
        PostTarget.allCases.filter(person.hasAccount(on:))
    }

    private var handles: String {
        [person.mastodonAcct, person.blueskyHandle].compactMap { $0.map { "@" + $0 } }.joined(separator: " · ")
    }
}

/// Suggestions for the @-mention being typed, shown under the editor while a
/// query is active. The text view keeps focus; arrow keys and Return drive it.
struct MentionSuggestionList: View {
    let completion: MentionCompletion

    var body: some View {
        if completion.isActive {
            VStack(alignment: .leading, spacing: 1) {
                if let message = completion.failureMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                ForEach(Array(completion.people.enumerated()), id: \.offset) { index, person in
                    // A tap, not a Button, so clicking leaves focus in the text view;
                    // VoiceOver still gets a button it can activate.
                    MentionPersonRow(person: person, selected: index == completion.selectedIndex)
                        .onTapGesture { completion.choose(person) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { completion.choose(person) }
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mention suggestions")
        }
    }
}
