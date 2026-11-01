import SwiftUI

/// Something the keyboard can do in a focused feed list.
enum FeedKeyCommand: Equatable {
    case next, previous, pageDown, pageUp
    case open, back
    case reply, like, repost
    /// Moves the keyboard to a network's feed column.
    case focus(PostTarget)

    /// The command for a key pressed in a focused feed list, or nil when the key is
    /// unbound. Nothing fires with ⌘, ⌃ or ⌥ held, so menu shortcuts keep their keys,
    /// and Delete is never bound.
    init?(key: KeyEquivalent, characters: String, modifiers: EventModifiers) {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let shifted = modifiers.contains(.shift)
        if key == .space {
            self = shifted ? .pageUp : .pageDown
            return
        }
        guard !shifted else { return nil }
        switch key {
        case .downArrow: self = .next
        case .upArrow: self = .previous
        case .leftArrow: self = .focus(.mastodon)
        case .rightArrow: self = .focus(.bluesky)
        case .return: self = .open
        case .escape: self = .back
        default:
            // Caps Lock sends capitals without Shift; they mean the same key.
            switch characters.lowercased() {
            case "j": self = .next
            case "k": self = .previous
            case "r": self = .reply
            case "l": self = .like
            case "b": self = .repost
            default: return nil
            }
        }
    }
}

/// Moves a feed list's keyboard focus. Focus is anchored to a post id rather than an
/// index, so posts inserted above (a refresh) leave the same post focused.
enum FeedNavigation {
    /// Rows to page by when the list hasn't reported which rows are on screen.
    static let fallbackPage = 5

    /// The post `offset` rows from `selection`, clamped to the ends of the list.
    /// Without a selection that's still in the list, focus starts on the first post
    /// on screen, where the reader is looking.
    static func move(from selection: String?, by offset: Int, in ids: [String],
                     visible: Set<String>) -> String? {
        guard let selection, let index = ids.firstIndex(of: selection) else {
            return firstVisible(in: ids, visible: visible)
        }
        return ids[clamped(index + offset, in: ids)]
    }

    /// One screen of posts forward or back: down to the first post below the visible
    /// ones, or up by as many posts as are visible. Always moves at least one post.
    static func page(forward: Bool, from selection: String?, in ids: [String],
                     visible: Set<String>) -> String? {
        let shown = ids.indices.filter { visible.contains(ids[$0]) }
        guard let first = shown.first, let last = shown.last else {
            return move(from: selection, by: forward ? fallbackPage : -fallbackPage,
                        in: ids, visible: visible)
        }
        guard let selection, let index = ids.firstIndex(of: selection) else {
            return firstVisible(in: ids, visible: visible)
        }
        let target = forward ? max(last + 1, index + 1) : min(first - shown.count, index - 1)
        return ids[clamped(target, in: ids)]
    }

    static func firstVisible(in ids: [String], visible: Set<String>) -> String? {
        ids.first { visible.contains($0) } ?? ids.first
    }

    private static func clamped(_ index: Int, in ids: [String]) -> Int {
        min(max(index, 0), ids.count - 1)
    }
}

/// Which feed column holds the keyboard. Each column's visible list claims a request
/// for its network, so focus follows pushes and pops and moves between columns.
@MainActor
@Observable
final class FeedKeyboardFocus {
    /// The column that holds, or last held, the keyboard.
    var lastFeed: PostTarget = .mastodon
    /// A column asked to take the keyboard and not yet claimed by its list.
    private(set) var pending: PostTarget?

    func request(_ target: PostTarget) {
        pending = target
    }

    /// True once, for the list that takes a pending request for `target`.
    func claim(_ target: PostTarget) -> Bool {
        guard pending == target else { return false }
        pending = nil
        return true
    }
}

/// What a post list needs from its column to take part in keyboard navigation.
struct FeedListContext {
    let target: PostTarget
    /// True for the list on top of the column's route stack.
    let isActive: Bool
    /// Pops the column's route stack; nil on the column's root feed.
    let pop: (() -> Void)?
}

/// The focused feed list's commands, for the Post menu.
struct FeedListCommands {
    let selectedPost: FeedPost?
    let canGoBack: Bool
    let perform: (FeedKeyCommand) -> Void
}

extension FocusedValues {
    @Entry var feedListCommands: FeedListCommands?
    /// The window's feed focus, so the Post menu can move the keyboard to a feed
    /// even from the composer.
    @Entry var feedKeyboardFocus: FeedKeyboardFocus?
}

extension EnvironmentValues {
    @Entry var feedListContext: FeedListContext?
    /// The post that draws the keyboard focus ring: set only while its list has focus.
    @Entry var keyboardFocusedPostID: String?
    /// Lets a clicked row take its list's keyboard focus.
    @Entry var selectFeedPost: ((String) -> Void)?
    /// Escape in the composer's editor: hands the keyboard back to the last feed.
    @Entry var composerEscape: (() -> Void)?
}
