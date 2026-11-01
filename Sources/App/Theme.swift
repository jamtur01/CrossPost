import AppKit
import SwiftUI

extension PostTarget {
    /// Network accent for text, links, and glyphs: the brand hue (Mastodon Blurple
    /// #6364FF, Bluesky blue #0A7AFF) deepened in light mode and lifted in dark mode
    /// so small text clears 4.5:1 on the feed background and its hover fill.
    /// Used sparingly: the column identity glyph, links, active states.
    var accent: Color {
        switch self {
        case .mastodon: .adaptive(light: 0x5354E8, dark: 0x8C8DFF)
        case .bluesky: .adaptive(light: 0x0066D6, dark: 0x4DA3FF)
        }
    }

    /// The accent for filled surfaces under white text (your own DM bubbles,
    /// prominent buttons): the deeper shade in both appearances, so the white label
    /// keeps 5.4:1 where the dark-mode text accent would drop it below 3:1.
    var fillAccent: Color {
        switch self {
        case .mastodon: Color(nsColor: NSColor(hex: 0x5354E8))
        case .bluesky: Color(nsColor: NSColor(hex: 0x0066D6))
        }
    }

    /// A small letter-mark badge for the column header.
    var glyph: String {
        switch self {
        case .mastodon: "m.circle.fill"
        case .bluesky: "b.circle.fill"
        }
    }
}

/// Central design tokens. macOS type scale (content a touch larger for readability,
/// à la Ice Cubes), an 8pt-ish spacing grid, and semantic surfaces so colour stays
/// restrained and light/dark adapt without manual inversion.
enum Theme {
    // Typography
    static let columnTitle = Font.system(size: 15, weight: .semibold)
    static let columnSubtitle = Font.system(size: 12, weight: .medium) // feed or route under the title
    static let timelineName = Font.system(size: 14, weight: .semibold)
    static let timelineHandle = Font.system(size: 12.5)
    static let timelineMeta = Font.system(size: 12.5)
    static let timelineContext = Font.system(size: 12, weight: .medium)
    // Post body sizes; `readingFont` adds the Reading text size setting on top.
    static let timelineContentSize: CGFloat = 14
    static let contentSize: CGFloat = 15 // composer, sheets, bios, DMs
    static let expandedContentSize: CGFloat = 18
    static let content = Font.system(size: contentSize)
    static let name = Font.system(size: 14.5, weight: .semibold)
    static let nameLarge = Font.system(size: 16, weight: .semibold)
    static let handle = Font.system(size: 13) // @handle (secondary)
    static let meta = Font.system(size: 12.5) // timestamp (secondary)
    static let context = Font.system(size: 12, weight: .medium) // "boosted" / "in reply"
    static let action = Font.system(size: 13.5)
    static let count = Font.system(size: 12.5).monospacedDigit()
    static let sectionHeader = Font.system(size: 11, weight: .semibold) // "People" / "Pinned"

    // Metrics (8pt-ish grid)
    static let timelineRowPaddingH: CGFloat = 14
    static let timelineRowPaddingV: CGFloat = 10
    static let rowPaddingH: CGFloat = 16
    static let rowPaddingV: CGFloat = 12
    static let headerPaddingH: CGFloat = 14
    static let componentSpacing: CGFloat = 6
    static let gutter: CGFloat = 10 // avatar → content
    static let actionGap: CGFloat = 20 // between action buttons
    static let actionGapNarrow: CGFloat = 12 // when the standard gap would overflow a narrow column
    static let timelineAvatar: CGFloat = 40
    static let avatar: CGFloat = 44
    static let avatarSmall: CGFloat = 42 // list rows (search/followers)
    static let avatarLarge: CGFloat = 54
    static let cardCorner: CGFloat = 12
    static let mediaCorner: CGFloat = 10 // media, embeds, and fields and labels at that scale
    static let insetCorner: CGFloat = 8 // sheet editors, suggestion lists, quote previews, CW rows
    static let highlightCorner: CGFloat = 6 // a selected row inside an inset list
    static let skeletonCorner: CGFloat = 4
    static let bubbleCorner: CGFloat = 15 // DM bubbles
    static let bodyLineSpacing: CGFloat = 3
    static let sheetWidth: CGFloat = 420

    // Surfaces — hierarchy through subtle fills + hairlines, never loud borders.
    static let hairline = Color.primary.opacity(0.07)
    static let hoverFill = Color.primary.opacity(0.04)
    static let avatarRing = Color.primary.opacity(0.08)
    /// The focused row's ring: the user's accent at full strength. The system focus
    /// colour is that accent at about half opacity, too faint on the white feed, so
    /// light mode also deepens it a fifth toward black to keep it clear on white.
    static let focusRing = Color(nsColor: NSColor(name: nil) { appearance in
        var accent = NSColor.controlAccentColor
        appearance.performAsCurrentDrawingAppearance {
            accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? accent
        }
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? accent : accent.blended(withFraction: 0.2, of: .black) ?? accent
    })
    // Action tints — shared by the timeline and notification action bars so
    // like/repost read identically everywhere they appear.
    // The system pink and green fall to 2–3.6:1 as count text on white, so light mode
    // takes deeper shades; every value clears 4.5:1 on the row and its hover fill.
    static let likeTint = Color.adaptive(light: 0xD1194A, dark: 0xFF5C7E)
    static let repostTint = Color.adaptive(light: 0x157A33, dark: 0x30D158)
}

extension Color {
    /// An sRGB colour that resolves per appearance, so text tints can differ
    /// between light and dark mode (including the high-contrast variants).
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// A softly bordered semantic surface used for the compose card and previews.
private struct CardSurface: ViewModifier {
    var corner: CGFloat = Theme.cardCorner

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.75)
            )
    }
}

extension View {
    func cardSurface(corner: CGFloat = Theme.cardCorner) -> some View {
        modifier(CardSurface(corner: corner))
    }
}

/// Trackpad haptic feedback for engagement actions (like, repost), matching the
/// subtle tick Apple's own apps give. No-op on Macs without a Force Touch trackpad.
enum Haptics {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

/// A reading preference applied to post bodies, quotations, bios, and messages.
enum ReadingTextSize: String, CaseIterable {
    case standard = "Standard"
    case larger = "Larger"
    case largest = "Largest"

    static let storageKey = "readingTextSize"

    var increase: CGFloat {
        switch self {
        case .standard: 0
        case .larger: 2
        case .largest: 4
        }
    }
}

private struct ReadingFont: ViewModifier {
    @AppStorage(ReadingTextSize.storageKey, store: AccountStore.defaults) private var size = ReadingTextSize.standard
    let baseSize: CGFloat

    func body(content: Content) -> some View {
        content.font(.system(size: baseSize + size.increase))
    }
}

extension View {
    func readingFont(size: CGFloat = Theme.contentSize) -> some View {
        modifier(ReadingFont(baseSize: size))
    }
}
