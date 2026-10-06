import AppKit
import SwiftUI

/// Text that draws Mastodon custom emoji (":shortcode:") as inline images.
/// A shortcode shows as text until its image loads, and stays text if it fails.
struct EmojiText: View {
    let text: AttributedString
    let emojis: [String: URL]
    /// Point size of the surrounding font; emoji are drawn to sit in its line.
    let pointSize: CGFloat
    @State private var loaded: [URL: NSImage] = [:]

    init(_ text: AttributedString, emojis: [String: URL], pointSize: CGFloat) {
        self.text = text
        self.emojis = emojis
        self.pointSize = pointSize
    }

    init(_ text: String, emojis: [String: URL], pointSize: CGFloat) {
        self.init(AttributedString(text), emojis: emojis, pointSize: pointSize)
    }

    var body: some View {
        if emojis.isEmpty {
            Self.linkMarked(text)
        } else {
            let segments = CustomEmoji.segments(in: text, emojis: emojis)
            let urls = Self.urls(in: segments)
            compose(segments)
                .task(id: urls) { await load(urls) }
        }
    }

    private func compose(_ segments: [CustomEmoji.Segment]) -> Text {
        segments.map(text(for:)).reduce(Text(verbatim: ""), +)
    }

    private func text(for segment: CustomEmoji.Segment) -> Text {
        switch segment {
        case let .text(run):
            return Self.linkMarked(run)
        case let .emoji(shortcode, url):
            guard let image = image(for: url) else { return Text(verbatim: ":\(shortcode):") }
            return Text(Image(nsImage: sized(image))).baselineOffset(pointSize * -0.2)
        }
    }

    /// Tags each link run with `LinkRun` so `linkPointers()` can find its bounds.
    private static func linkMarked(_ text: AttributedString) -> Text {
        guard #available(macOS 15, *), text.runs.contains(where: { $0.link != nil }) else {
            return Text(text)
        }
        return text.runs[\.link].map { link, range in
            let piece = Text(AttributedString(text[range]))
            return link.map { piece.customAttribute(LinkRun(url: $0)) } ?? piece
        }
        .reduce(Text(verbatim: ""), +)
    }

    private func image(for url: URL) -> NSImage? {
        loaded[url] ?? BoundedImageLoader.shared.cachedImage(for: Self.request(url))
    }

    /// Scales the emoji to the line height, keeping its aspect ratio. The drawing
    /// handler redraws from the decoded pixels, so it stays sharp on Retina.
    private func sized(_ image: NSImage) -> NSImage {
        let height = (pointSize * 1.2).rounded()
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let size = NSSize(width: (height * aspect).rounded(), height: height)
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    private func load(_ urls: Set<URL>) async {
        for url in urls where image(for: url) == nil {
            do {
                loaded[url] = try await BoundedImageLoader.shared.image(for: Self.request(url))
            } catch {
                guard !Task.isCancelled else { return }
                Log.feed.debug("Custom emoji \(url, privacy: .public) did not load: \(error)")
            }
        }
    }

    private static func urls(in segments: [CustomEmoji.Segment]) -> Set<URL> {
        var urls: Set<URL> = []
        for segment in segments {
            if case let .emoji(_, url) = segment {
                urls.insert(url)
            }
        }
        return urls
    }

    /// One decode size for every text size, so all uses share the cached image.
    private static func request(_ url: URL) -> ImageRequest {
        ImageRequest(url: url, representation: .avatar, targetSize: CGSize(width: 64, height: 64))
    }
}
