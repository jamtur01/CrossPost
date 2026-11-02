import SwiftUI

/// A post action affordance: an SF Symbol, an optional compact count, an active
/// (engaged) tint, and a tooltip. Shared by the timeline and notification rows.
///
/// - Parameters:
///   - symbol: SF Symbol name.
///   - count: When provided, shows a compact count beside the icon (timeline style).
///   - toggle: For a toggle (like, repost, bookmark), the stable name VoiceOver reads
///     with an On or Off value, and whether it is engaged; nil for a plain action
///     such as Reply.
///   - tint: Colour applied when the toggle is engaged.
///   - help: Tooltip naming what a click does next, and the VoiceOver label of a
///     plain action.
///   - compact: When true, uses the notification-row font and hides counts.
///   - action: Callback invoked on tap.
@MainActor
func postActionButton(
    _ symbol: String,
    count: Int? = nil,
    toggle: (name: String, isOn: Bool)? = nil,
    tint: Color,
    help: String,
    compact: Bool = false,
    action: @escaping () -> Void
) -> some View {
    let active = toggle?.isOn ?? false
    let state = toggle.map { $0.isOn ? "On" : "Off" }
    let value = [state, count.map { $0.formatted() }]
        .compactMap(\.self).joined(separator: ", ")
    return Button(action: action) {
        HStack(spacing: 5) {
            // Engaged actions also get a heavier stroke so the state doesn't rest on
            // colour alone (Repost has no filled symbol, unlike Like's heart.fill).
            Image(systemName: symbol)
                .font(compact ? .system(size: 13) : Theme.action)
                .fontWeight(active ? .bold : .regular)
            if !compact, let count, count > 0 {
                Text(count.formatted(.number.notation(.compactName)))
                    .font(Theme.count)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(active ? tint : Color.secondary)
        .frame(minWidth: 28, minHeight: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(toggle?.name ?? help)
    .accessibilityValue(value)
    .accessibilityAddTraits(active ? .isSelected : [])
    .help(help)
}

/// The like, repost, and bookmark titles, shared by the action bars' tooltips and,
/// for like and repost, the Post menu. Each names what a click does next.
extension FeedPost {
    /// The network's word for reposting, which is also the toggle's VoiceOver name.
    var repostVerb: String {
        target == .mastodon ? "Boost" : "Repost"
    }

    var likeTitle: String {
        isLiked ? "Unlike" : "Like"
    }

    var repostTitle: String {
        isReposted ? "Undo \(repostVerb)" : repostVerb
    }

    var bookmarkTitle: String {
        isBookmarked ? "Remove Bookmark" : "Bookmark"
    }
}
