import SwiftUI

/// The Post menu: every feed keyboard binding, so they can be found in the menu bar
/// and in Help's menu search. The keys sit in the titles rather than as menu key
/// equivalents: AppKit matches a bare-key equivalent before the focused text view
/// sees the key (even on a disabled item), which would swallow typing in the
/// composer and sheets. The keys themselves are handled by the focused feed list.
struct FeedCommands: Commands {
    @FocusedValue(\.feedListCommands) private var list
    @FocusedValue(\.feedKeyboardFocus) private var keyboardFocus

    var body: some Commands {
        CommandMenu("Post") {
            command("Next Post", keys: "J or ↓", .next)
            command("Previous Post", keys: "K or ↑", .previous)
            command("Page Down", keys: "Space", .pageDown)
            command("Page Up", keys: "⇧Space", .pageUp)
            Divider()
            command("Open Thread", keys: "Return", .open, needsPost: true)
            command("Back", keys: "Esc", .back)
                .disabled(list?.canGoBack != true)
            Divider()
            command("Reply", keys: "R", .reply, needsPost: true)
            command(likeTitle, keys: "L", .like, needsPost: true)
            command(repostTitle, keys: "B", .repost, needsPost: true)
            Divider()
            focusButton(.mastodon, keys: "←")
            focusButton(.bluesky, keys: "→")
        }
    }

    private func command(_ title: String, keys: String, _ command: FeedKeyCommand,
                         needsPost: Bool = false) -> some View {
        Button("\(title) (\(keys))") { list?.perform(command) }
            .disabled(list == nil || (needsPost && list?.selectedPost == nil))
    }

    private func focusButton(_ target: PostTarget, keys: String) -> some View {
        Button("\(target.displayName) Feed (\(keys))") { keyboardFocus?.request(target) }
            .disabled(keyboardFocus == nil)
    }

    private var likeTitle: String {
        list?.selectedPost?.isLiked == true ? "Unlike" : "Like"
    }

    private var repostTitle: String {
        let verb = list?.selectedPost?.target == .mastodon ? "Boost" : "Repost"
        return list?.selectedPost?.isReposted == true ? "Undo \(verb)" : verb
    }
}
