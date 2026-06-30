import SwiftUI

/// A centered icon + message, used for empty and error states across the app so
/// they stay consistent. `fills` centers it in a full pane; otherwise it sits at
/// its natural height (for use inside a scrolling list).
struct EmptyStateView: View {
    let text: String
    var systemImage = "tray"
    var fills = true
    /// When set, a "Try Again" button is shown — used for error states.
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil)
        .padding(fills ? 16 : 0)
        .padding(.vertical, fills ? 0 : 40)
    }
}

/// A failed-fetch state with a retry button, in the shared visual language.
struct ErrorStateView: View {
    let message: String
    var fills = true
    let retry: () -> Void

    var body: some View {
        EmptyStateView(text: message, systemImage: "exclamationmark.triangle",
                       fills: fills, retry: retry)
    }
}

/// A subtle fill that appears on hover, for clickable list rows so they read as
/// interactive like the timeline rows do.
private struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(hovering ? Theme.hoverFill : .clear)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

/// A circular avatar with the shared placeholder + ring, used everywhere an
/// account image appears so sizing and the hairline ring stay consistent.
struct AvatarView: View {
    let url: URL?
    var size: CGFloat
    var ring = true

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if ring { Circle().strokeBorder(Theme.avatarRing, lineWidth: 0.5) }
        }
    }
}

/// A relative ("2m", "1h") timestamp in the shared meta styling.
func relativeTimestamp(_ date: Date) -> some View {
    Text(date, format: .relative(presentation: .numeric))
        .font(Theme.meta).foregroundStyle(.tertiary).fixedSize()
}
