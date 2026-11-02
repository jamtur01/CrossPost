import SwiftUI

extension FeedPostView {
    /// Runs a reveal change, animated unless Reduce Motion is on.
    func changeReveal(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2), change)
    }

    func contentWarningRow(_ warning: String) -> some View {
        ContentWarningRow(warning: warning, emojis: post.emojis, fontSize: bodyFontSize,
                          accent: accent, isShown: reveals.showsContent(of: post)) {
            changeReveal { reveals.toggleContent(of: post) }
        }
    }

    /// Stand-in for a covered media item: a tiny preview scaled up and blurred, so
    /// nothing recognizable is ever decoded. Its footprint comes from the media's
    /// declared aspect ratio, so revealing it doesn't shift the layout. Motion media
    /// has no still unless the server sent a preview image.
    func coveredMedia(_ media: FeedImage, fit: Bool) -> some View {
        let still = media.previewURL ?? (media.kind == .image ? media.url : nil)
        return coveredFootprint(media, fit: fit)
            .overlay {
                CachedAsyncImage(url: still, representation: .thumbnail,
                                 targetSize: CGSize(width: 16, height: 16)) { image in
                    image.resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .blur(radius: 12, opaque: true)
                } placeholder: {
                    Theme.placeholderFill
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func coveredFootprint(_ media: FeedImage, fit: Bool) -> some View {
        if fit {
            Color.clear.aspectRatio(media.aspectRatio ?? 1.5, contentMode: .fit)
        } else {
            Color.clear
        }
    }

    /// The cover over sensitive media until the reader shows it.
    @ViewBuilder
    var sensitiveMediaCover: some View {
        if !reveals.showsMedia(of: post) {
            Button { changeReveal { reveals.toggleMedia(of: post) } } label: {
                SensitiveMediaLabel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Show sensitive media")
            .accessibilityLabel(post.images.count == 1 ? "Sensitive media, hidden"
                : "\(post.images.count) sensitive media items, hidden")
            .accessibilityHint("Shows the media")
        }
    }

    /// The link card thumbnail's share of the post's media reveal; nil unless sensitive.
    var cardSensitiveMedia: LinkCardView.SensitiveMedia? {
        guard post.isSensitive else { return nil }
        return LinkCardView.SensitiveMedia(isShown: reveals.showsMedia(of: post)) {
            changeReveal { reveals.toggleMedia(of: post) }
        }
    }

    /// Covers shown sensitive media again; drawn on the first media item.
    @ViewBuilder
    func hideSensitiveMediaButton(on media: FeedImage) -> some View {
        if post.isSensitive, media.id == post.images.first?.id {
            HideSensitiveMediaButton { changeReveal { reveals.toggleMedia(of: post) } }
        }
    }
}

/// Covers shown sensitive media again: a small capsule over the media's corner.
struct HideSensitiveMediaButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 20)
                .background(.black.opacity(0.55), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(8)
        .help("Hide sensitive media")
        .accessibilityLabel("Hide sensitive media")
    }
}

/// A content warning standing in for the post until the reader opens it.
/// The whole row toggles, so it is an easy target; the warning reads in the body
/// font so the Reading text size setting reaches it.
struct ContentWarningRow: View {
    let warning: String
    let emojis: [String: URL]
    let fontSize: CGFloat
    let accent: Color
    let isShown: Bool
    let toggle: () -> Void
    @AppStorage(ReadingTextSize.storageKey, store: AccountStore.defaults)
    private var readingSize = ReadingTextSize.standard

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                EmojiText(warning, emojis: emojis, pointSize: fontSize + readingSize.increase)
                    .readingFont(size: fontSize)
                    .fontWeight(.medium)
                    .lineSpacing(Theme.bodyLineSpacing)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(isShown ? "Hide post" : "Show post")
                    .font(Theme.timelineContext)
                    .foregroundStyle(accent)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.hoverFill, in: RoundedRectangle(cornerRadius: Theme.insetCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.insetCorner, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(isShown ? "Hide post" : "Show post")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Content warning: \(warning)")
        .accessibilityValue(isShown ? "Post shown" : "Post hidden")
        .accessibilityHint(isShown ? "Hides the post" : "Shows the post")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, toggle)
    }
}

/// The centered notice drawn over blurred sensitive media.
struct SensitiveMediaLabel: View {
    var body: some View {
        VStack(spacing: 2) {
            Label("Sensitive content", systemImage: "eye.slash.fill")
                .font(.system(size: 12.5, weight: .semibold))
            Text("Click to show")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
    }
}
