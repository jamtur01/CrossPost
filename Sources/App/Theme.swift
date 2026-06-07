import SwiftUI

extension PostTarget {
    /// Brand accent — Mastodon "Blurple" (#6364FF), Bluesky blue (#0A7AFF).
    /// Used sparingly: the column identity glyph, active states, and primary actions.
    var accent: Color {
        switch self {
        case .mastodon: return Color(red: 0.388, green: 0.392, blue: 1.0)
        case .bluesky: return Color(red: 0.039, green: 0.478, blue: 1.0)
        }
    }

    /// A small letter-mark badge for the column header.
    var glyph: String {
        switch self {
        case .mastodon: return "m.circle.fill"
        case .bluesky: return "b.circle.fill"
        }
    }
}

/// Central design tokens. macOS type scale (content a touch larger for readability,
/// à la Ice Cubes), an 8pt-ish spacing grid, and semantic surfaces so colour stays
/// restrained and light/dark adapt without manual inversion.
enum Theme {
    // Typography
    static let columnTitle = Font.system(size: 15, weight: .semibold)
    static let content = Font.system(size: 15)                        // post body
    static let contentLarge = Font.system(size: 18)                   // detail body
    static let name = Font.system(size: 14.5, weight: .semibold)
    static let nameLarge = Font.system(size: 16, weight: .semibold)
    static let handle = Font.system(size: 13)                         // @handle (secondary)
    static let meta = Font.system(size: 12.5)                         // timestamp (tertiary)
    static let context = Font.system(size: 12, weight: .medium)       // "boosted" / "in reply"
    static let action = Font.system(size: 13.5)
    static let count = Font.system(size: 12.5).monospacedDigit()

    // Metrics (8pt-ish grid)
    static let rowPaddingH: CGFloat = 16
    static let rowPaddingV: CGFloat = 12
    static let headerPaddingH: CGFloat = 14
    static let componentSpacing: CGFloat = 6
    static let gutter: CGFloat = 10                                   // avatar → content
    static let actionGap: CGFloat = 20                               // between action buttons
    static let avatar: CGFloat = 44
    static let avatarLarge: CGFloat = 54
    static let cardCorner: CGFloat = 12
    static let mediaCorner: CGFloat = 10
    static let bodyLineSpacing: CGFloat = 3

    // Surfaces — hierarchy through subtle fills + hairlines, never loud borders.
    static let hairline = Color.primary.opacity(0.07)
    static let hoverFill = Color.primary.opacity(0.04)
    static let avatarRing = Color.primary.opacity(0.08)
}

/// A layered, softly bordered surface — the macOS card look (hairline definition
/// edge + soft shadow, no heavy border). Used for the compose card and previews.
private struct CardSurface: ViewModifier {
    var corner: CGFloat = Theme.cardCorner
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.75))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

extension View {
    func cardSurface(corner: CGFloat = Theme.cardCorner) -> some View {
        modifier(CardSurface(corner: corner))
    }
}
