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
                    AsyncImage(url: imageURL) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(card.url.absoluteString)
    }
}

/// A quoted post rendered as a nested card, with a leading accent rule. Opens the original.
struct QuoteCardView: View {
    let quote: QuotedPost
    let accent: Color
    let onOpen: (URL) -> Void

    private var hasText: Bool { !quote.text.characters.isEmpty }

    var body: some View {
        Button { if let url = quote.webURL { onOpen(url) } } label: {
            HStack(spacing: 0) {
                Capsule().fill(accent.opacity(0.55)).frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        AsyncImage(url: quote.avatarURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(.quaternary)
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                        Text(quote.authorName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Text(quote.authorHandle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if hasText {
                        Text(RichText.styled(quote.text, accent: accent))
                            .font(.system(size: 13))
                            .tint(accent)
                            .lineLimit(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let imageURL = quote.imageURL {
                        AsyncImage(url: imageURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
