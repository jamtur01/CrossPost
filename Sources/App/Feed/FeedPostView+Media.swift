import SwiftUI

extension FeedPostView {
    /// Indicator for a non-public post (Mastodon visibility). Public posts and
    /// Bluesky posts (which have no per-post visibility) show nothing.
    var visibilityBadge: (symbol: String, label: String)? {
        switch post.visibility {
        case "unlisted": ("moon", "Unlisted")
        case "private": ("lock.fill", "Followers only")
        case "direct": ("envelope.fill", "Direct message")
        default: nil
        }
    }

    @ViewBuilder
    var images: some View {
        if !post.images.isEmpty {
            if expanded {
                VStack(spacing: 8) {
                    ForEach(post.images) { media in
                        mediaView(media, fit: true)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
                    }
                }
            } else {
                timelineMedia
            }
        }
    }

    /// Timeline media mosaic: one image fills the column at a capped height; two to
    /// four tile into a grid with hairline gaps and rounded outer corners; a fifth+
    /// collapses into a "+N" overlay on the last tile.
    @ViewBuilder
    private var timelineMedia: some View {
        let imgs = post.images
        Group {
            switch imgs.count {
            case 1:
                mediaView(imgs[0], fit: true)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 300)
            case 2:
                HStack(spacing: 3) { gridTile(imgs[0]); gridTile(imgs[1]) }
                    .frame(height: 180)
            case 3:
                HStack(spacing: 3) {
                    gridTile(imgs[0])
                    VStack(spacing: 3) { gridTile(imgs[1]); gridTile(imgs[2]) }
                }
                .frame(height: 220)
            default:
                VStack(spacing: 3) {
                    HStack(spacing: 3) { gridTile(imgs[0]); gridTile(imgs[1]) }
                    HStack(spacing: 3) {
                        gridTile(imgs[2])
                        gridTile(imgs[3]).overlay { overflowBadge(extra: imgs.count - 4) }
                    }
                }
                .frame(height: 250)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
    }

    /// A single equal-weight mosaic cell that fills its slot. The image rides as an
    /// overlay on a size-neutral `Color.clear`, so an aspect-fill image (whose ideal
    /// size exceeds the slot to cover it) fills and clips without widening the tile —
    /// otherwise that oversized ideal propagates up and makes the card exceed its column.
    private func gridTile(_ media: FeedImage) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { mediaView(media, fit: false) }
            .clipped()
            .contentShape(Rectangle())
    }

    /// "+N" scrim on the last tile when a post carries more images than the grid shows.
    @ViewBuilder
    private func overflowBadge(extra: Int) -> some View {
        if extra > 0 {
            ZStack {
                Color.black.opacity(0.45)
                Text("+\(extra)").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func mediaView(_ media: FeedImage, fit: Bool) -> some View {
        switch media.kind {
        case .image:
            staticImage(media, fit: fit)
                .accessibilityLabel(media.altText.isEmpty ? "Image" : media.altText)
        case .gif:
            MotionMedia(media: media, fit: fit, badge: "GIF") { active in
                AnimatedGIFView(
                    url: media.url,
                    previewURL: media.previewURL,
                    fit: fit,
                    isActive: active
                )
            }
        case .video:
            MotionMedia(media: media, fit: fit, badge: nil) { active in
                LoopingVideoView(url: media.url,
                                 gravity: fit ? .resizeAspect : .resizeAspectFill, isActive: active)
            }
        }
    }

    private func staticImage(_ media: FeedImage, fit: Bool) -> some View {
        let previewURL = media.previewURL ?? media.url
        let targetSize = fit ? CGSize(width: 1600, height: 1200)
            : CGSize(width: 1200, height: 1200)
        return CachedAsyncImage(
            url: previewURL,
            representation: .timeline,
            targetSize: targetSize
        ) { phase in staticImageContent(phase, media: media, fit: fit) }
            .onTapGesture { lightbox?.present(media.url) }
            .pointingHandCursor(enabled: lightbox != nil)
            .draggable(media.url) {
                CachedAsyncImage(
                    url: previewURL,
                    representation: .thumbnail,
                    targetSize: CGSize(width: 160, height: 160)
                ) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
            }
    }

    @ViewBuilder
    private func staticImageContent(
        _ phase: CachedAsyncImagePhase, media: FeedImage, fit: Bool
    ) -> some View {
        switch phase {
        case let .success(image):
            image.resizable().aspectRatio(contentMode: fit ? .fit : .fill)
        case .loading:
            reservedMediaPlaceholder(media, fit: fit).shimmering()
        case .failure:
            reservedMediaPlaceholder(media, fit: fit)
                .overlay { Image(systemName: "photo.badge.exclamationmark") }
        case .unavailable:
            reservedMediaPlaceholder(media, fit: fit)
        }
    }

    @ViewBuilder
    private func reservedMediaPlaceholder(_ media: FeedImage, fit: Bool) -> some View {
        if fit, let aspect = media.aspectRatio {
            RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .aspectRatio(aspect, contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 120)
        }
    }
}
