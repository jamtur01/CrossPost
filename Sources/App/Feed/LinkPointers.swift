import SwiftUI

/// Marks a link run inside a `Text`, so its laid-out bounds can be found.
@available(macOS 15, *)
struct LinkRun: TextAttribute {
    let url: URL
}

/// Puts a pointing-hand hit area over each link in selectable text. Selectable
/// `Text` forces the I-beam over its whole frame (links included), and no cursor
/// set from a hover handler survives it, so links need their own views on top.
/// Clicks on them open through the environment's `openURL`, as the text would.
@available(macOS 15, *)
private struct LinkPointers: ViewModifier {
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(Text.LayoutKey.self) { layouts in
            GeometryReader { proxy in
                let links = Self.links(in: layouts, proxy: proxy)
                ForEach(links.indices, id: \.self) { index in
                    let link = links[index]
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: link.rect.width, height: link.rect.height)
                        .pointerStyle(.link)
                        .help(link.url.absoluteString)
                        .onTapGesture { openURL(link.url) }
                        .position(x: link.rect.midX, y: link.rect.midY)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Link run bounds in the overlay's space, clipped to it so a line cut off by
    /// a line limit can't catch clicks meant for the views below.
    private static func links(
        in layouts: [Text.LayoutKey.AnchoredLayout], proxy: GeometryProxy
    ) -> [(rect: CGRect, url: URL)] {
        let bounds = CGRect(origin: .zero, size: proxy.size)
        var links: [(rect: CGRect, url: URL)] = []
        for anchored in layouts {
            let origin = proxy[anchored.origin]
            for line in anchored.layout {
                for run in line {
                    guard let url = run[LinkRun.self]?.url else { continue }
                    let rect = run.typographicBounds.rect
                        .offsetBy(dx: origin.x, dy: origin.y)
                        .intersection(bounds)
                    if !rect.isEmpty {
                        links.append((rect, url))
                    }
                }
            }
        }
        return links
    }
}

extension View {
    /// Pointing-hand cursor over the links of an `EmojiText` (macOS 15+; earlier
    /// systems keep the text's own cursor).
    @ViewBuilder
    func linkPointers() -> some View {
        if #available(macOS 15, *) {
            modifier(LinkPointers())
        } else {
            self
        }
    }
}
