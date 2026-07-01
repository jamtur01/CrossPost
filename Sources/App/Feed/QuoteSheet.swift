import SwiftUI

/// Composes a quote post embedding `post`, on the post's own network. Text only;
/// the caller supplies the platform call via `submit`.
struct QuoteSheet: View {
    let post: FeedPost
    var accent: Color = .accentColor
    let submit: (String, PostVisibility) async throws -> Void
    let onClose: () -> Void
    @EnvironmentObject private var store: AccountStore

    @State private var text = ""
    @State private var visibility: PostVisibility = .public
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private var limit: Int {
        post.target == .bluesky ? TargetLimits.blueskyMax : store.mastodonMaxChars
    }
    private var count: Int { PostValidator.graphemeCount(text) }
    private var counterColor: Color {
        if count > limit { return .red }
        if count >= limit - 20 { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(icon: nil, label: "Quote on \(post.target.displayName)", accent: accent)

            PlainTextEditor(text: $text)
                .frame(minHeight: 80)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Add a comment…")
                            .font(Theme.content).foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            quotedPreview

            HStack {
                if post.target == .mastodon {
                    VisibilityMenu(visibility: $visibility, accent: accent)
                }
                Spacer()
                Text("\(count)/\(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(counterColor)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            SheetFooter(
                sending: isSending, sent: sent,
                successLabel: "Quote posted", submitLabel: "Quote", submittingLabel: "Posting…",
                canSubmit: count <= limit, onCancel: onClose, onSubmit: send)
        }
        .sheetContainer()
    }

    private var quotedPreview: some View {
        QuotedPreviewBlock(post: post, accent: accent)
    }

    private func send() {
        isSending = true
        errorMessage = nil
        Task {
            defer { isSending = false }
            do {
                try await submit(text, visibility)
                sent = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                onClose()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}
