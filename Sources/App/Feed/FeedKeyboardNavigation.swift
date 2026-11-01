import AppKit
import SwiftUI

/// Keyboard navigation for a scrolling list of rows (posts, notifications, people,
/// conversations, messages): the list takes keyboard focus, one row in it carries the
/// focus ring, and keys move or act on that row. Apply to the `ScrollView`, whose lazy
/// stack must be a `.scrollTargetLayout()`; rows draw the ring with
/// `keyboardFocusIndicator(id:)`.
private struct KeyboardListNavigation: ViewModifier {
    let ids: [String]
    let initialSelection: String?
    /// The post a row is about, for R/L/B and the Post menu.
    let post: (String) -> FeedPost?
    let open: (String) -> Void
    /// R, L or B on a row that has a post.
    let act: (FeedKeyCommand, String) -> Void

    @Environment(\.feedListContext) private var context
    @Environment(FeedKeyboardFocus.self) private var keyboardFocus: FeedKeyboardFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var selection: String?
    @State private var visible: Set<String> = []

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.98) {
                    visible = Set($0)
                }
                .environment(\.keyboardFocusedRowID, isFocused ? selection : nil)
                .environment(\.selectKeyboardRow, StableAction { select($0) })
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .focusedValue(\.feedListCommands, FeedListCommands(
                    hasSelection: selectedID != nil, selectedPost: selectedPost, canGoBack: context?.pop != nil,
                    perform: { perform($0, proxy: proxy) }
                ))
                .onKeyPress { press in
                    handle(press, proxy: proxy)
                }
                .onAppear(perform: claimFocus)
                .onChange(of: context?.isActive) { claimFocus() }
                .onChange(of: keyboardFocus?.pending) { claimFocus() }
                .onChange(of: isFocused) { focusChanged() }
        }
    }

    /// The selection while its row is still in the list.
    private var selectedID: String? {
        selection.flatMap { ids.contains($0) ? $0 : nil }
    }

    private var selectedPost: FeedPost? {
        selectedID.flatMap(post)
    }

    private func handle(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !Self.isEditingText,
              let command = FeedKeyCommand(key: press.key, characters: press.characters,
                                           modifiers: press.modifiers),
              command != .back || context?.pop != nil,
              !command.needsPost || selectedPost != nil else { return .ignored }
        perform(command, proxy: proxy)
        return .handled
    }

    private func perform(_ command: FeedKeyCommand, proxy: ScrollViewProxy) {
        switch command {
        case .next:
            show(FeedNavigation.move(from: selection, by: 1, in: ids, visible: visible), proxy)
        case .previous:
            show(FeedNavigation.move(from: selection, by: -1, in: ids, visible: visible), proxy)
        case .pageDown:
            show(FeedNavigation.page(forward: true, from: selection, in: ids, visible: visible), proxy)
        case .pageUp:
            show(FeedNavigation.page(forward: false, from: selection, in: ids, visible: visible), proxy)
        case .open:
            guard let id = selectedID else { return }
            handFocusToColumn()
            open(id)
        case .back:
            guard let pop = context?.pop else { return }
            handFocusToColumn()
            pop()
        case let .focus(target):
            keyboardFocus?.request(target)
        case .reply, .like, .repost:
            guard let id = selectedID, selectedPost != nil else { return }
            act(command, id)
        }
    }

    /// Focuses `id`, scrolling it to the top when it isn't wholly on screen. Top, not
    /// nearest edge, so a post taller than the column still shows from its start.
    private func show(_ id: String?, _ proxy: ScrollViewProxy) {
        selection = id
        guard let id, !visible.contains(id) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    /// A clicked row takes the focus, and the thread it opens inherits the keyboard.
    private func select(_ id: String) {
        selection = id
        isFocused = true
        handFocusToColumn()
    }

    /// Asks whichever list is on top of this column next (after a push or pop) to
    /// take the keyboard.
    private func handFocusToColumn() {
        guard let target = context?.target else { return }
        keyboardFocus?.request(target)
    }

    /// Takes the keyboard when asked to, showing the ring at once on the post the list
    /// would start from. Focus that arrives another way (Tab, a click on a button)
    /// waits for a key before choosing a post.
    private func claimFocus() {
        guard let context, context.isActive, keyboardFocus?.claim(context.target) == true else { return }
        isFocused = true
        if selectedID == nil {
            selection = initialSelection ?? FeedNavigation.firstVisible(in: ids, visible: visible)
        }
    }

    private func focusChanged() {
        if isFocused, let target = context?.target {
            keyboardFocus?.lastFeed = target
        }
    }

    /// Belt and braces for "never while typing": SwiftUI only routes keys here while
    /// the list has focus, but an editable AppKit text view as first responder means
    /// the user is typing, whatever SwiftUI thinks.
    private static var isEditingText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable == true
    }
}

extension View {
    /// Adds keyboard navigation to a scrolling list of rows; see `KeyboardListNavigation`.
    /// `initialSelection` is the row focused first (a thread's own post).
    func keyboardListNavigation(ids: [String], initialSelection: String? = nil,
                                post: @escaping (String) -> FeedPost? = { _ in nil },
                                act: @escaping (FeedKeyCommand, String) -> Void = { _, _ in },
                                open: @escaping (String) -> Void) -> some View {
        modifier(KeyboardListNavigation(ids: ids, initialSelection: initialSelection,
                                        post: post, open: open, act: act))
    }

    /// Keyboard navigation for a list of posts whose likes and reposts belong to
    /// `hosts` (a profile has two).
    func feedKeyboardNavigation(posts: [FeedPost], initialSelection: String? = nil,
                                hosts: [any OptimisticPostHost], reply: @escaping (FeedPost) -> Void,
                                open: @escaping (FeedPost) -> Void) -> some View {
        let post = { (id: String) in posts.first { $0.id == id } }
        return keyboardListNavigation(
            ids: posts.map(\.id), initialSelection: initialSelection, post: post,
            act: { command, id in post(id).map { performPostKey(command, on: $0, hosts: hosts, reply: reply) } },
            open: { id in post(id).map(open) }
        )
    }

    /// Draws the keyboard focus ring over the row with `id` while its list has focus,
    /// and moves VoiceOver to it.
    func keyboardFocusIndicator(id: String) -> some View {
        modifier(KeyboardFocusIndicator(id: id))
    }
}

/// R, L or B on a post, through the same toggles as the row's action bar (haptic tick
/// included).
@MainActor
func performPostKey(_ command: FeedKeyCommand, on post: FeedPost, hosts: [any OptimisticPostHost],
                    reply: (FeedPost) -> Void) {
    let host = hosts.first { $0.posts.contains { $0.id == post.id } }
    switch command {
    case .reply: reply(post)
    case .like: host?.toggleLike(post)
    case .repost: host?.toggleRepost(post)
    case .next, .previous, .pageDown, .pageUp, .open, .back, .focus: break
    }
}

private struct KeyboardFocusIndicator: ViewModifier {
    let id: String
    @Environment(\.keyboardFocusedRowID) private var focusedID
    @AccessibilityFocusState private var voiceOverFocused: Bool

    func body(content: Content) -> some View {
        let hasFocus = focusedID == id
        content
            .overlay {
                if hasFocus {
                    KeyboardFocusRing()
                }
            }
            // VoiceOver follows the keyboard: the focused row is one element group.
            .accessibilityElement(children: .contain)
            .accessibilityFocused($voiceOverFocused)
            .onChange(of: hasFocus, initial: true) { _, hasFocus in
                if hasFocus {
                    voiceOverFocused = true
                }
            }
    }
}

/// The system keyboard focus ring, inset so the column edges never clip it.
struct KeyboardFocusRing: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Theme.focusRing, lineWidth: 3)
            .padding(2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
