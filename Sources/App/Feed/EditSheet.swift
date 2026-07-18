import SwiftUI

/// The load + submit calls an edit needs, bundled so a post row carries one
/// optional value. Present only for posts the platform can edit (your own
/// Mastodon posts).
struct PostEditActions {
    let load: () async throws -> EditableSource
    let submit: (_ text: String, _ spoiler: String) async throws -> Void
}

/// Edit actions for a post if it's your own Mastodon post; nil otherwise (Bluesky
/// has no edit). Centralizes the per-row check the feed surfaces share. `onUpdated`
/// receives the edited post so a PostList-backed route (thread/profile/search/saved)
/// can replace its own row, since those don't observe the panel timeline refresh.
@MainActor
func postEditActions(for post: FeedPost, _ panel: FeedPanelModel,
                     onUpdated: @escaping (FeedPost) -> Void = { _ in }) -> PostEditActions? {
    guard post.target == .mastodon, panel.isMine(post) else { return nil }
    return PostEditActions(
        load: { try await panel.editableSource(of: post) },
        submit: { text, spoiler in
            let updated = try await panel.edit(post: post, text: text, spoiler: spoiler)
            onUpdated(updated)
        })
}

/// Edits one of your own posts: loads the raw source, lets you change the text
/// and content warning, and submits. Media is preserved by the service.
struct EditSheet: View {
    let post: FeedPost
    var accent: Color = .accentColor
    let actions: PostEditActions
    let onClose: () -> Void
    @EnvironmentObject private var store: AccountStore

    @State private var text = ""
    @State private var spoiler = ""
    @State private var hasSpoiler = false
    @State private var loading = true
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    // Edits are Mastodon-only (postEditActions gates on it), so the connected
    // instance's limit always applies.
    private var limit: Int { store.mastodonMaxChars }
    private var count: Int { PostValidator.graphemeCount(text) }
    private var canSave: Bool {
        !isSending && !sent && count <= limit
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !post.images.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(icon: "pencil", label: "Edit post", accent: accent)

            if loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                editor
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            SheetFooter(
                sending: isSending, sent: sent,
                successLabel: "Saved", submitLabel: "Save", submittingLabel: "Saving…",
                canSubmit: canSave, onCancel: onClose, onSubmit: save)
        }
        .sheetContainer()
        .task {
            do {
                let source = try await actions.load()
                text = source.text
                spoiler = source.spoiler
                hasSpoiler = !source.spoiler.isEmpty
            } catch {
                errorMessage = error.userMessage
            }
            loading = false
        }
    }

    @ViewBuilder
    private var editor: some View {
        if hasSpoiler {
            TextField("Content warning", text: $spoiler)
                .textFieldStyle(.roundedBorder)
        }

        SheetTextEditor(text: $text, minHeight: 110)

        HStack {
            Button {
                hasSpoiler.toggle()
                if !hasSpoiler { spoiler = "" }
            } label: {
                Label(hasSpoiler ? "Remove content warning" : "Add content warning",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Spacer()
            Text("\(count)/\(limit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(counterColor(count: count, limit: limit))
        }
    }

    private func save() {
        submitSheet(isSending: $isSending, sent: $sent, errorMessage: $errorMessage,
                    onClose: onClose) {
            try await actions.submit(text, hasSpoiler ? spoiler : "")
        }
    }
}
