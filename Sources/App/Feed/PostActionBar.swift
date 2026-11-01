import SwiftUI

/// A post action affordance: an SF Symbol, an optional compact count, an active
/// (engaged) tint, and a tooltip. Shared by the timeline and notification rows.
///
/// - Parameters:
///   - symbol: SF Symbol name.
///   - count: When provided, shows a compact count beside the icon (timeline style).
///   - active: Whether the action is currently engaged (e.g. liked, reposted, bookmarked).
///   - tint: Colour applied when `active` is true.
///   - help: Accessibility tooltip.
///   - compact: When true, uses the notification-row font and hides counts.
///   - action: Callback invoked on tap.
@MainActor
func postActionButton(
    _ symbol: String,
    count: Int? = nil,
    active: Bool = false,
    tint: Color,
    help: String,
    compact: Bool = false,
    action: @escaping () -> Void
) -> some View {
    let isToggle = ["heart", "heart.fill", "arrow.2.squarepath"].contains(symbol)
    let isBookmark = symbol.hasPrefix("bookmark")
    let state = if isBookmark {
        active ? "Bookmarked" : ""
    } else {
        isToggle ? (active ? "On" : "Off") : ""
    }
    let value = [state, count.map { $0.formatted() } ?? ""]
        .filter { !$0.isEmpty }.joined(separator: ", ")
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
    .accessibilityLabel(help)
    .accessibilityValue(value)
    .accessibilityAddTraits(active ? .isSelected : [])
    .help(help)
}
