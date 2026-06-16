import SwiftUI

/// A centered icon + message, used for empty and error states across the app so
/// they stay consistent. `fills` centers it in a full pane; otherwise it sits at
/// its natural height (for use inside a scrolling list).
struct EmptyStateView: View {
    let text: String
    var systemImage = "tray"
    var fills = true

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil)
        .padding(fills ? 16 : 0)
        .padding(.vertical, fills ? 0 : 40)
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
