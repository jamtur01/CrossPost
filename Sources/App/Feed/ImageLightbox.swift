import SwiftUI

/// Window-level state for the full-screen image popout. A single instance lives
/// at the app root and is injected into the environment, so any view can call
/// `present(_:)` to pop an image out over a dimmed backdrop.
@Observable
final class ImageLightbox {
    struct Item: Equatable {
        let url: URL
        var isCircular: Bool
    }

    private(set) var item: Item?

    func present(_ url: URL, circular: Bool = false) {
        withAnimation(.easeOut(duration: 0.2)) {
            item = Item(url: url, isCircular: circular)
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { item = nil }
    }
}

/// The dimmed backdrop and enlarged image. Click anywhere or press Escape to
/// dismiss. Sized relative to the window so it always leaves a margin.
struct ImageLightboxOverlay: View {
    let lightbox: ImageLightbox

    var body: some View {
        if let item = lightbox.item {
            GeometryReader { geo in
                ZStack {
                    Rectangle().fill(.black.opacity(0.72)).ignoresSafeArea()
                    image(item, in: geo.size)
                        .shadow(color: .black.opacity(0.4), radius: 30)
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onTapGesture { lightbox.dismiss() }
            }
            .transition(.opacity)
            .onExitCommand { lightbox.dismiss() }
        }
    }

    /// A circular avatar fills a square; a photo fits within the window's bounds
    /// so the whole image is visible at its natural aspect ratio.
    @ViewBuilder
    private func image(_ item: ImageLightbox.Item, in size: CGSize) -> some View {
        if item.isCircular {
            let side = min(size.width, size.height) * 0.72
            AsyncImage(url: item.url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                ProgressView().controlSize(.large).tint(.white)
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
        } else {
            AsyncImage(url: item.url) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                ProgressView().controlSize(.large).tint(.white)
            }
            .frame(maxWidth: size.width * 0.92, maxHeight: size.height * 0.92)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
