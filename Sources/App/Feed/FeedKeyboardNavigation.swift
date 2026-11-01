import AppKit
import SwiftUI

/// Keyboard navigation for a scrolling list of `FeedRow`s: the list takes keyboard
/// focus, one post in it carries the focus ring, and keys move or act on that post.
/// Apply to the `ScrollView`, whose lazy stack must be a `.scrollTargetLayout()`.
private struct FeedKeyboardNavigation: ViewModifier {
    let posts: [FeedPost]
    let initialSelection: String?
    let open: (FeedPost) -> Void

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
                .environment(\.keyboardFocusedPostID, isFocused ? selection : nil)
                .environment(\.selectFeedPost) { select($0) }
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onKeyPress { press in
                    handle(press, proxy: proxy)
                }
                .onAppear(perform: claimFocus)
                .onChange(of: context?.isActive) { claimFocus() }
                .onChange(of: keyboardFocus?.pending) { claimFocus() }
                .onChange(of: isFocused) { focusChanged() }
        }
    }

    private var ids: [String] {
        posts.map(\.id)
    }

    private var selectedPost: FeedPost? {
        posts.first { $0.id == selection }
    }

    private func handle(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !Self.isEditingText,
              let command = FeedKeyCommand(key: press.key, characters: press.characters,
                                           modifiers: press.modifiers),
              command != .back || context?.pop != nil else { return .ignored }
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
            guard let post = selectedPost else { return }
            handFocusToColumn()
            open(post)
        case .back:
            guard let pop = context?.pop else { return }
            handFocusToColumn()
            pop()
        case let .focus(target):
            keyboardFocus?.request(target)
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

    private func claimFocus() {
        guard let context, context.isActive, keyboardFocus?.claim(context.target) == true else { return }
        isFocused = true
    }

    private func focusChanged() {
        guard isFocused else { return }
        if let target = context?.target {
            keyboardFocus?.lastFeed = target
        }
        if selectedPost == nil {
            selection = initialSelection ?? FeedNavigation.firstVisible(in: ids, visible: visible)
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
    /// Adds keyboard navigation to a scrolling list of posts; see `FeedKeyboardNavigation`.
    /// `initialSelection` is the post focused first (a thread's own post).
    func feedKeyboardNavigation(posts: [FeedPost], initialSelection: String? = nil,
                                open: @escaping (FeedPost) -> Void) -> some View {
        modifier(FeedKeyboardNavigation(posts: posts, initialSelection: initialSelection, open: open))
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
