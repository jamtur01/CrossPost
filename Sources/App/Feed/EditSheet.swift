import SwiftUI

/// The load + submit calls an edit needs, bundled so a post row carries one
/// optional value. Present only for posts the platform can edit (your own
/// Mastodon posts).
struct PostEditActions {
    let load: () async throws -> EditableSource
    let submit: (_ text: String, _ spoiler: String) async throws -> Void
}

/// Edit actions for a post if it's your own Mastodon post; nil otherwise (Bluesky
/// has no edit). Centralizes the per-row check the feed surfaces share.
@MainActor
func postEditActions(for post: FeedPost, _ panel: FeedPanelModel) -> PostEditActions? {
    guard post.target == .mastodon, panel.isMine(post) else { return nil }
    return PostEditActions(
        load: { try await panel.editableSource(of: post) },
        submit: { text, spoiler in _ = try await panel.edit(post: post, text: text, spoiler: spoiler) })
}

/// Edits one of your own posts: loads the raw source, lets you change the text
/// and content warning, and submits. Media is preserved by the service.
struct EditSheet: View {
    let post: FeedPost
    var accent: Color = .accentColor
    let actions: PostEditActions
    let onClose: () -> Void

    @State private var text = ""
    @State private var spoiler = ""
    @State private var hasSpoiler = false
    @State private var loading = true
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private var limit: Int { TargetLimits.mastodonFallback }
    private var count: Int { PostValidator.graphemeCount(text) }
    private var counterColor: Color {
        if count > limit { return .red }
        if count >= limit - 20 { return .orange }
        return .secondary
    }
    private var canSave: Bool {
        !sending && !sent
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !post.images.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "pencil").foregroundStyle(accent)
                Text("Edit post").font(.headline)
            }

            if loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                editor
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                if sent {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                }
                Spacer()
                Button("Cancel", action: onClose).disabled(sending || sent)
                Button(sending ? "Saving…" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
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

        PlainTextEditor(text: $text)
            .frame(minHeight: 110)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

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
                .foregroundStyle(counterColor)
        }
    }

    private func save() {
        sending = true
        errorMessage = nil
        Task {
            defer { sending = false }
            do {
                try await actions.submit(text, hasSpoiler ? spoiler : "")
                sent = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                onClose()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}
