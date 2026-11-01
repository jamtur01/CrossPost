import SwiftUI

/// The menu bar's shortcuts, named once for the menus and the Keyboard Shortcuts panel.
extension KeyboardShortcut {
    static let newPost = KeyboardShortcut("n")
    static let toggleComposer = KeyboardShortcut("c", modifiers: [.command, .shift])
    static let refreshAll = KeyboardShortcut("r")
    static let showHome = KeyboardShortcut("1")
    static let showNotifications = KeyboardShortcut("2")
    static let showMessages = KeyboardShortcut("3")
    static let keyboardShortcuts = KeyboardShortcut("/")
}

/// One line of the Keyboard Shortcuts panel: what happens, and the keys that do it.
struct ShortcutRow: Identifiable {
    let action: String
    let keys: [ShortcutKey]

    var id: String {
        action
    }

    init(_ action: String, _ keys: ShortcutKey...) {
        self.action = action
        self.keys = keys
    }

    init(_ action: String, _ shortcut: KeyboardShortcut) {
        self.init(action, ShortcutKey(shortcut))
    }

    init(_ binding: FeedKeyBinding) {
        action = Self.action(for: binding.command)
        keys = binding.keys
    }

    private static func action(for command: FeedKeyCommand) -> String {
        switch command {
        case .next: "Next item"
        case .previous: "Previous item"
        case .pageDown: "Page down"
        case .pageUp: "Page up"
        case .open: "Open the thread, profile, or conversation"
        case .back: "Go back"
        case .reply: "Reply to the post"
        case .like: "Like or unlike the post"
        case .repost: "Boost or repost the post"
        case let .focus(target): "Move to the \(target.displayName) column"
        }
    }
}

/// A titled group of rows, by where the keys work.
struct ShortcutGroup: Identifiable {
    let title: String
    var note: String?
    let rows: [ShortcutRow]

    var id: String {
        title
    }
}

/// Every shortcut the panel lists. List and column keys come from
/// `FeedKeyCommand.bindings` and menu keys from the `KeyboardShortcut` constants the
/// menus use, so the panel shows the keys that actually work.
enum ShortcutCatalog {
    static var groups: [ShortcutGroup] {
        let bindings = FeedKeyCommand.bindings
        let listKeys = bindings.filter { !$0.command.isColumnFocus }
        let columnKeys = bindings.filter(\.command.isColumnFocus)
        return [
            ShortcutGroup(
                title: "Lists",
                note: "Home, notifications, threads, profiles, saved posts, search results, and "
                    + "messages. Click a row or press Esc in the composer to give a list the "
                    + "keyboard. Single keys never act while you type.",
                rows: listKeys.map(ShortcutRow.init)
            ),
            ShortcutGroup(title: "Columns", rows: columnKeys.map(ShortcutRow.init) + [
                ShortcutRow("Show Home in both columns", .showHome),
                ShortcutRow("Show Notifications in both columns", .showNotifications),
                ShortcutRow("Show Messages in both columns", .showMessages),
                ShortcutRow("Refresh both columns", .refreshAll)
            ]),
            ShortcutGroup(title: "Composer", rows: [
                ShortcutRow("New post", .newPost),
                ShortcutRow("Show or hide the composer", .toggleComposer),
                ShortcutRow("Post", ShortcutKey(.return, .command)),
                ShortcutRow("Return to the last list", ShortcutKey(.escape))
            ]),
            ShortcutGroup(title: "Search and Messages", rows: [
                ShortcutRow("Move from the search field to the results", ShortcutKey(.escape)),
                ShortcutRow("Move from the message field to the conversation", ShortcutKey(.escape)),
                ShortcutRow("Send the message", ShortcutKey(.return))
            ]),
            ShortcutGroup(title: "Window", rows: [
                ShortcutRow("Keyboard Shortcuts", .keyboardShortcuts),
                ShortcutRow("Settings", ShortcutKey(",", .command))
            ])
        ]
    }
}

extension FeedKeyCommand {
    var isColumnFocus: Bool {
        if case .focus = self {
            return true
        }
        return false
    }
}

/// Help › Keyboard Shortcuts: a panel listing every shortcut by where it works.
/// Esc or ⌘W closes it.
struct KeyboardShortcutsView: View {
    static let windowID = "keyboard-shortcuts"

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            ForEach(ShortcutCatalog.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        LabeledContent(row.action) {
                            KeyCaps(keys: row.keys)
                        }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if let note = group.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 360, idealHeight: 640)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }
}

/// Help › Keyboard Shortcuts (⌘/).
struct KeyboardShortcutsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Keyboard Shortcuts") { openWindow(id: KeyboardShortcutsView.windowID) }
            .keyboardShortcut(.keyboardShortcuts)
    }
}

/// A shortcut's keys drawn as key caps, alternatives separated by "or".
private struct KeyCaps: View {
    let keys: [ShortcutKey]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys.indices, id: \.self) { index in
                if index > 0 {
                    Text("or").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    ForEach(keys[index].capSymbols, id: \.self) { KeyCap(content: $0) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.map(\.spokenText).joined(separator: " or "))
    }
}

private struct KeyCap: View {
    let content: ShortcutKey.Cap

    var body: some View {
        Group {
            switch content {
            case let .symbol(name): Image(systemName: name)
            case let .text(text): Text(text)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.primary)
        .frame(minWidth: 22, minHeight: 20)
        .padding(.horizontal, 4)
        .background(Theme.hoverFill, in: RoundedRectangle(cornerRadius: Theme.skeletonCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.skeletonCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
        }
    }
}

private extension ShortcutKey {
    enum Cap: Hashable {
        case symbol(String)
        case text(String)
    }

    /// One cap per modifier, then the key: SF Symbols where the key has one.
    var capSymbols: [Cap] {
        let caps = heldModifiers.map { Cap.symbol($0.symbol) }
        let symbols: [KeyEquivalent: String] = [
            .upArrow: "arrow.up", .downArrow: "arrow.down", .leftArrow: "arrow.left",
            .rightArrow: "arrow.right", .return: "return", .escape: "escape"
        ]
        return caps + [symbols[key].map(Cap.symbol) ?? .text(keyName)]
    }

    /// The shortcut as VoiceOver reads it, such as "Shift Space".
    var spokenText: String {
        let names: [KeyEquivalent: String] = [
            .upArrow: "Up Arrow", .downArrow: "Down Arrow", .leftArrow: "Left Arrow",
            .rightArrow: "Right Arrow", .escape: "Escape"
        ]
        let words = heldModifiers.map(\.spoken) + [names[key] ?? keyName]
        return words.joined(separator: " ")
    }
}
