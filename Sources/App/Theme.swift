import SwiftUI

extension PostTarget {
    /// Brand accent — Mastodon "Blurple" (#6364FF), Bluesky blue (#0A7AFF).
    var accent: Color {
        switch self {
        case .mastodon: return Color(red: 0.388, green: 0.392, blue: 1.0)
        case .bluesky: return Color(red: 0.039, green: 0.478, blue: 1.0)
        }
    }
}

/// Central design tokens. Sizes follow the macOS type scale (slightly larger
/// content than chrome, à la Ice Cubes) and an 8pt spacing grid. Colours are
/// semantic so light and dark mode adapt without manual inversion.
enum Theme {
    // Typography
    static let content = Font.system(size: 15)                       // post body
    static let contentLarge = Font.system(size: 19)                  // detail body
    static let name = Font.system(size: 14, weight: .semibold)
    static let nameLarge = Font.system(size: 16, weight: .semibold)
    static let meta = Font.system(size: 12.5)                        // handle, time
    static let context = Font.system(size: 12, weight: .medium)      // "boosted" / "in reply"
    static let action = Font.system(size: 13)

    // Metrics (8pt grid)
    static let rowPaddingH: CGFloat = 16
    static let rowPaddingV: CGFloat = 11
    static let componentSpacing: CGFloat = 7
    static let avatar: CGFloat = 46
    static let avatarLarge: CGFloat = 56
    static let cardCorner: CGFloat = 12
    static let mediaCorner: CGFloat = 12
}

/// A layered, lightly bordered surface — the macOS card look (0.5px definition
/// edge + soft shadow). Used for the compose card and sheet previews.
private struct CardSurface: ViewModifier {
    var corner: CGFloat = Theme.cardCorner
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 1)
    }
}

extension View {
    func cardSurface(corner: CGFloat = Theme.cardCorner) -> some View {
        modifier(CardSurface(corner: corner))
    }
}
