import SwiftUI

/// The muted reference block shown while composing a reply or quote: an accent
/// rule, the author handle, and a few lines of the post. Intentionally not
/// tappable — it is context, so focus stays on the compose field.
struct QuotedPreviewBlock: View {
    let post: FeedPost
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Capsule().fill(accent.opacity(0.5)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.authorHandle).font(.caption.bold()).foregroundStyle(.secondary)
                Text(post.text).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
            .padding(.leading, 10)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
    }
}
