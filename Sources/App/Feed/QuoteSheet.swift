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
    @State private var sending = false
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
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text("Quote on \(post.target.displayName)").font(.headline)
            }

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

            HStack {
                if sent {
                    Label("Quote posted", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                }
                Spacer()
                Button("Cancel", action: onClose).disabled(sending || sent)
                Button(sending ? "Posting…" : "Quote") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(sending || sent || count > limit)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var quotedPreview: some View {
        HStack(alignment: .top, spacing: 0) {
            Capsule().fill(accent.opacity(0.5)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.authorHandle).font(.caption.bold()).foregroundStyle(.secondary)
                Text(post.text).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
            .padding(.leading, 10)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
    }

    private func send() {
        sending = true
        errorMessage = nil
        Task {
            defer { sending = false }
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
