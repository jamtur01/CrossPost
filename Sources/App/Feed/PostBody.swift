import SwiftUI

/// The canonical reading treatment for a post body: tappable, accent-coloured
/// mentions/links, shared line spacing, in-app link routing, and text selection.
/// Every reading surface (timeline, thread, notifications, quote embed, search,
/// profile) renders through this so they stay consistent.
struct PostBody: View {
    let text: AttributedString
    let accent: Color
    var cacheKey: String?
    var font: Font = Theme.content
    var color: AnyShapeStyle = AnyShapeStyle(.primary)
    var lineLimit: Int?
    let onOpenURL: (URL) -> Void

    var body: some View {
        Text(RichText.styled(text, accent: accent, cacheKey: cacheKey))
            .font(font)
            .foregroundStyle(color)
            .tint(accent)
            .lineSpacing(Theme.bodyLineSpacing)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            // No fixedSize when a line limit is set — they conflict and the text
            // would ignore the limit and grow unbounded.
            .fixedSize(horizontal: false, vertical: lineLimit == nil)
            .environment(\.openURL, OpenURLAction { url in onOpenURL(url); return .handled })
            .textSelection(.enabled)
    }
}
