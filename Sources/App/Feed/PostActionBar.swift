import SwiftUI

/// A post action affordance: an SF Symbol, an optional compact count, an active
/// (engaged) tint, and a tooltip. Shared by the timeline and notification rows.
///
/// - Parameters:
///   - symbol: SF Symbol name.
///   - count: When provided, shows a compact count beside the icon (timeline style).
///   - active: Whether the action is currently engaged (e.g. liked, reposted).
///   - tint: Colour applied when `active` is true.
///   - help: Accessibility tooltip.
///   - compact: When true, uses notification-row sizing: `.system(size: 13)` font
///     and a fixed `22×18` frame instead of `Theme.action` font with padding.
///   - action: Callback invoked on tap.
@ViewBuilder
func postActionButton(
    _ symbol: String,
    count: Int? = nil,
    active: Bool = false,
    tint: Color,
    help: String,
    compact: Bool = false,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        if compact {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(active ? tint : .secondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        } else if let count {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(Theme.action)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(active ? tint : Color.secondary)
                if count > 0 {
                    Text(count.formatted(.number.notation(.compactName)))
                        .font(Theme.count)
                        .foregroundStyle(active ? tint : Color.secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .animation(.snappy, value: active)
        } else {
            Image(systemName: symbol)
                .font(Theme.action)
                .foregroundStyle(active ? tint : .secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 5)
                .contentShape(Rectangle())
        }
    }
    .buttonStyle(.plain)
    .help(help)
}
