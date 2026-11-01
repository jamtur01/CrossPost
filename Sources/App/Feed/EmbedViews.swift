import SwiftUI

/// A link preview card — thumbnail, title, description, and domain. Opens the URL.
struct LinkCardView: View {
    let card: LinkCard
    var accent: Color = .accentColor
    let onOpen: (URL) -> Void

    var body: some View {
        Button { onOpen(card.url) } label: {
            HStack(spacing: 0) {
                if let imageURL = card.imageURL {
                    EmbedImage(
                        url: imageURL,
                        targetSize: CGSize(width: 184, height: 184)
                    )
                    .frame(width: 92, height: 92)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.providerName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Text(card.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if !card.description.isEmpty {
                        Text(card.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(card.url.absoluteString)
    }
}

/// A quoted post rendered as a nested card, with a leading accent rule. Opens the original.
/// The quoted post's content warning and sensitive media stay covered until revealed,
/// as they would be on the post itself.
struct QuoteCardView: View {
    let quote: QuotedPost
    let accent: Color
    let reveals: PostReveals
    let onOpen: (URL) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasText: Bool {
        !quote.text.characters.isEmpty
    }

    var body: some View {
        // Only present as tappable when there's a URL to open; otherwise it's a
        // plain card, not a dead button.
        if let url = quote.webURL {
            Button { onOpen(url) } label: { card }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Open quoted post")
        } else {
            card
        }
    }

    private var card: some View {
        HStack(spacing: 0) {
            Capsule().fill(accent.opacity(0.55)).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AvatarView(url: quote.avatarURL, size: 20, ring: false)
                    EmojiText(quote.authorName, emojis: quote.emojis, pointSize: 12.5)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(quote.authorHandle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let warning = quote.contentWarning {
                    ContentWarningRow(warning: warning, emojis: quote.emojis, fontSize: 13, accent: accent,
                                      isShown: reveals.showsContent(of: quote)) {
                        changeReveal { reveals.toggleContent(of: quote) }
                    }
                }
                if reveals.showsContent(of: quote) {
                    if hasText {
                        PostBody(text: quote.text, accent: accent, cacheKey: quote.id, emojis: quote.emojis,
                                 fontSize: 13, lineLimit: 6,
                                 onTap: quote.webURL.map { url in { onOpen(url) } },
                                 onOpenURL: onOpen)
                    }
                    if let imageURL = quote.imageURL {
                        image(imageURL)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    /// The quoted image, or a plain cover while it is sensitive and not yet shown;
    /// the covered image is never loaded.
    private func image(_ url: URL) -> some View {
        Group {
            if reveals.showsMedia(of: quote) {
                EmbedImage(url: url, targetSize: CGSize(width: 1000, height: 240))
                    .overlay(alignment: .topLeading) {
                        if quote.isSensitive {
                            HideSensitiveMediaButton { changeReveal { reveals.toggleMedia(of: quote) } }
                        }
                    }
            } else {
                Button { changeReveal { reveals.toggleMedia(of: quote) } } label: {
                    SensitiveMediaLabel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primary.opacity(0.06))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Show sensitive media")
                .accessibilityLabel("Sensitive media, hidden")
                .accessibilityHint("Shows the media")
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
    }

    private func changeReveal(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2), change)
    }
}

private struct EmbedImage: View {
    let url: URL
    let targetSize: CGSize

    var body: some View {
        CachedAsyncImage(
            url: url,
            representation: .thumbnail,
            targetSize: targetSize
        ) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .loading:
                Rectangle().fill(.quaternary).loadingSheen()
            case .failure:
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "photo.badge.exclamationmark") }
            case .unavailable:
                Rectangle().fill(.quaternary)
            }
        }
    }
}
