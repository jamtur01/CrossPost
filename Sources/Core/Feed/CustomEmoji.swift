import Foundation

/// Mastodon custom emoji: ":shortcode:" tokens in names and post text that the
/// server maps to images. Bluesky has none, so its emoji maps are always empty.
enum CustomEmoji {
    enum Segment: Equatable {
        case text(AttributedString)
        case emoji(shortcode: String, url: URL)
    }

    /// Splits `text` at every ":shortcode:" that `emojis` maps to an image.
    /// Unknown shortcodes stay as text, and text runs keep their attributes.
    static func segments(in text: AttributedString, emojis: [String: URL]) -> [Segment] {
        guard !emojis.isEmpty else { return [.text(text)] }
        let characters = text.characters
        var segments: [Segment] = []
        var cursor = characters.startIndex
        var searchStart = characters.startIndex
        while let open = characters[searchStart...].firstIndex(of: ":") {
            let afterOpen = characters.index(after: open)
            guard let close = characters[afterOpen...].firstIndex(of: ":") else { break }
            guard let url = emojis[String(characters[afterOpen ..< close])] else {
                // The closing colon may open the next shortcode ("10:30 :ok:").
                searchStart = close
                continue
            }
            if cursor < open {
                segments.append(.text(AttributedString(text[cursor ..< open])))
            }
            segments.append(.emoji(shortcode: String(characters[afterOpen ..< close]), url: url))
            cursor = characters.index(after: close)
            searchStart = cursor
        }
        if cursor < characters.endIndex {
            segments.append(.text(AttributedString(text[cursor...])))
        }
        return segments
    }
}
