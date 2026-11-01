import SwiftUI

/// Something the keyboard can do in a focused list.
enum FeedKeyCommand: Equatable {
    case next, previous, pageDown, pageUp
    case open, back
    case reply, like, repost
    /// Moves the keyboard to a network's column.
    case focus(PostTarget)

    /// The command for a key pressed in a focused list, or nil when the key is
    /// unbound. Nothing fires with ⌘, ⌃ or ⌥ held, so menu shortcuts keep their keys,
    /// and Delete is never bound.
    init?(key: KeyEquivalent, characters: String, modifiers: EventModifiers) {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let shift = modifiers.intersection(.shift)
        var pressed = [ShortcutKey(key, shift)]
        // Caps Lock sends capitals without Shift; they mean the same key.
        if characters.count == 1, let typed = characters.lowercased().first {
            pressed.append(ShortcutKey(KeyEquivalent(typed), shift))
        }
        guard let match = Self.bindings.first(where: { $0.keys.contains(where: pressed.contains) }) else {
            return nil
        }
        self = match.command
    }

    /// The keys a command answers to: the one table behind the key handling, the Post
    /// menu's titles, and the Keyboard Shortcuts panel, so none can drift.
    static let bindings: [FeedKeyBinding] = [
        FeedKeyBinding(.next, ShortcutKey("j"), ShortcutKey(.downArrow)),
        FeedKeyBinding(.previous, ShortcutKey("k"), ShortcutKey(.upArrow)),
        FeedKeyBinding(.pageDown, ShortcutKey(.space)),
        FeedKeyBinding(.pageUp, ShortcutKey(.space, .shift)),
        FeedKeyBinding(.open, ShortcutKey(.return)),
        FeedKeyBinding(.back, ShortcutKey(.escape)),
        FeedKeyBinding(.reply, ShortcutKey("r")),
        FeedKeyBinding(.like, ShortcutKey("l")),
        FeedKeyBinding(.repost, ShortcutKey("b")),
        FeedKeyBinding(.focus(.mastodon), ShortcutKey(.leftArrow)),
        FeedKeyBinding(.focus(.bluesky), ShortcutKey(.rightArrow))
    ]

    /// The command's keys as menu text, such as "J or ↓".
    var keysLabel: String {
        let keys = Self.bindings.first { $0.command == self }?.keys ?? []
        return keys.map(\.text).joined(separator: " or ")
    }

    /// R, L and B act on a post, so they need a row that has one.
    var needsPost: Bool {
        switch self {
        case .reply, .like, .repost: true
        case .next, .previous, .pageDown, .pageUp, .open, .back, .focus: false
        }
    }
}

/// One `FeedKeyCommand` and the keys bound to it.
struct FeedKeyBinding {
    let command: FeedKeyCommand
    let keys: [ShortcutKey]

    init(_ command: FeedKeyCommand, _ keys: ShortcutKey...) {
        self.command = command
        self.keys = keys
    }
}

/// A key and the modifiers held with it, as a binding names it and the Keyboard
/// Shortcuts panel draws it.
struct ShortcutKey: Equatable {
    let key: KeyEquivalent
    let modifiers: EventModifiers

    init(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    init(_ shortcut: KeyboardShortcut) {
        self.init(shortcut.key, shortcut.modifiers)
    }

    /// A modifier as a menu glyph, an SF Symbol, and a spoken word.
    struct Modifier {
        let flag: EventModifiers
        let glyph: String
        let symbol: String
        let spoken: String
    }

    /// The held modifiers in the menu bar's order: ⌃ ⌥ ⇧ ⌘.
    var heldModifiers: [Modifier] {
        let all = [
            Modifier(flag: .control, glyph: "⌃", symbol: "control", spoken: "Control"),
            Modifier(flag: .option, glyph: "⌥", symbol: "option", spoken: "Option"),
            Modifier(flag: .shift, glyph: "⇧", symbol: "shift", spoken: "Shift"),
            Modifier(flag: .command, glyph: "⌘", symbol: "command", spoken: "Command")
        ]
        return all.filter { modifiers.contains($0.flag) }
    }

    /// The key's name as text: a capital letter, an arrow, or a word.
    var keyName: String {
        switch key {
        case .space: "Space"
        case .return: "Return"
        case .escape: "Esc"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        default: String(key.character).uppercased()
        }
    }

    /// The whole shortcut as text, such as "⇧Space" or "⌘N".
    var text: String {
        heldModifiers.map(\.glyph).joined() + keyName
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
    /// A column's request for the keyboard. Each request is distinct, so asking for
    /// the same column again still changes `pending` and wakes the lists observing it.
    struct Request: Equatable {
        let target: PostTarget
        let serial: Int
        let date: Date
    }

    /// The column that holds, or last held, the keyboard.
    var lastFeed: PostTarget = .mastodon
    /// A column asked to take the keyboard and not yet claimed by its list.
    private(set) var pending: Request?
    private var serial = 0
    /// A request nobody claims (the column shows notifications) goes stale, so a list
    /// that appears later can't take the keyboard from wherever the user is typing.
    static let requestLifetime: TimeInterval = 1

    func request(_ target: PostTarget, now: Date = .now) {
        serial += 1
        pending = Request(target: target, serial: serial, date: now)
    }

    /// True once, for the list that takes a fresh pending request for `target`. A
    /// stale request is dropped by whichever list checks it.
    func claim(_ target: PostTarget, now: Date = .now) -> Bool {
        guard let pending else { return false }
        guard now.timeIntervalSince(pending.date) < Self.requestLifetime else {
            self.pending = nil
            return false
        }
        guard pending.target == target else { return false }
        self.pending = nil
        return true
    }
}

/// What a list needs from its column to take part in keyboard navigation.
struct FeedListContext {
    let target: PostTarget
    /// True for the list on top of the column's route stack.
    let isActive: Bool
    /// Pops the column's route stack; nil on the column's root feed.
    let pop: (() -> Void)?
}

/// The focused list's commands, for the Post menu.
struct FeedListCommands {
    /// Whether Open does something: a row is selected, or the list has an action for
    /// Return without one (an empty conversation focuses its message field).
    let canOpen: Bool
    /// The post the focused row is about; nil for a row without one (a follow, a person,
    /// a conversation).
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
    /// The row that draws the keyboard focus ring: set only while its list has focus.
    @Entry var keyboardFocusedRowID: String?
    /// Lets a clicked row take its list's keyboard focus.
    @Entry var selectKeyboardRow: StableAction<String>?
    /// Escape in the composer's editor: hands the keyboard back to the last feed.
    @Entry var composerEscape: StableAction<Void>?
}

/// A closure for the environment that compares equal to any other, so a parent
/// re-rendering doesn't invalidate every view that reads it. Only for closures whose
/// captures are stable (state storage, long-lived objects), where an older copy does
/// the same thing as a newer one.
struct StableAction<Input>: Equatable {
    let run: (Input) -> Void

    init(_ run: @escaping (Input) -> Void) {
        self.run = run
    }

    func callAsFunction(_ input: Input) {
        run(input)
    }

    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

extension StableAction where Input == Void {
    func callAsFunction() {
        run(())
    }
}
