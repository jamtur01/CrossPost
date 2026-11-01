import SwiftUI

/// The Post menu: every list keyboard binding (feeds, threads, profiles, saved posts,
/// notifications, search results, messages), so they can be found in the menu bar and
/// in Help's menu search. The keys sit in the titles rather than as menu key
/// equivalents: AppKit matches a bare-key equivalent before the focused text view
/// sees the key (even on a disabled item), which would swallow typing in the
/// composer, the search and message fields, and sheets. The keys themselves are
/// handled by the focused list.
struct FeedCommands: Commands {
    @FocusedValue(\.feedListCommands) private var list
    @FocusedValue(\.feedKeyboardFocus) private var keyboardFocus

    var body: some Commands {
        CommandMenu("Post") {
            command("Next Item", .next)
            command("Previous Item", .previous)
            command("Page Down", .pageDown)
            command("Page Up", .pageUp)
            Divider()
            command("Open", .open)
                .disabled(list?.hasSelection != true)
            command("Back", .back)
                .disabled(list?.canGoBack != true)
            Divider()
            command("Reply", .reply)
            command(likeTitle, .like)
            command(repostTitle, .repost)
            Divider()
            focusButton(.mastodon)
            focusButton(.bluesky)
        }
    }

    private func command(_ title: String, _ command: FeedKeyCommand) -> some View {
        Button("\(title) (\(command.keysLabel))") { list?.perform(command) }
            .disabled(list == nil || (command.needsPost && list?.selectedPost == nil))
    }

    private func focusButton(_ target: PostTarget) -> some View {
        Button("\(target.displayName) Column (\(FeedKeyCommand.focus(target).keysLabel))") {
            keyboardFocus?.request(target)
        }
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
