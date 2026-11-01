import SwiftUI

/// "N new posts": floats under the column header while posts that arrived above the
/// reader wait unread; clicking it scrolls to the top. The network accent marks only
/// the arrow, so the capsule stays a neutral material like the error toast.
struct NewPostsPill: View {
    let count: Int
    let target: PostTarget
    let action: () -> Void

    @State private var isHovering = false

    static func title(_ count: Int) -> String {
        count == 1 ? "1 new post" : "\(count) new posts"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(target.accent)
                Text(Self.title(count))
                    .font(Theme.timelineContext)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(Capsule(style: .continuous).fill(isHovering ? Theme.hoverFill : .clear))
                    .overlay(Capsule(style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75))
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Self.title(count))
        .accessibilityHint("Scrolls to the top of the timeline")
        .help("Scroll to the newest posts")
    }
}
