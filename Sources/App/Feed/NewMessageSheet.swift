import SwiftUI

/// Picks someone to message: searches the platform's accounts, then opens (or
/// creates) the conversation with the chosen one.
struct NewMessageSheet: View {
    let panel: FeedPanelModel
    let onOpen: (Conversation) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var candidates: [MentionCandidate] = []
    @State private var searchFailed = false
    @State private var searching = false
    @State private var opening: String?
    @State private var openTask: Task<Void, Never>?
    @State private var openError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(icon: "square.and.pencil", label: "New Message", accent: panel.target.accent)
            TextField("Search \(panel.target.displayName) accounts", text: $query)
                .textFieldStyle(.roundedBorder)
            results
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 280, alignment: .topLeading)
            if let openError {
                Text(openError).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .sheetContainer()
        .task(id: query) { await search() }
        .onDisappear { openTask?.cancel() }
    }

    @ViewBuilder
    private var results: some View {
        if searchFailed {
            Text("Couldn't search \(panel.target.displayName). Check the account in Settings.")
                .font(.callout).foregroundStyle(.secondary)
        } else if candidates.isEmpty {
            if searching {
                ProgressView().controlSize(.small)
            } else if trimmedQuery.count >= 2 {
                Text("No accounts found.").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(candidates, id: \.handle) { candidate in
                        Button { open(candidate) } label: {
                            HStack {
                                MentionPersonRow(person: person(for: candidate))
                                if opening == candidate.handle {
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(opening != nil)
                    }
                }
            }
        }
    }

    private var trimmedQuery: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    }

    private func person(for candidate: MentionCandidate) -> MentionPerson {
        MentionPerson(
            mastodonAcct: candidate.target == .mastodon ? candidate.handle : nil,
            blueskyHandle: candidate.target == .bluesky ? candidate.handle : nil,
            displayName: candidate.displayName,
            avatarURL: candidate.avatarURL
        )
    }

    private func search() async {
        let query = trimmedQuery
        guard query.count >= 2 else {
            candidates = []
            searchFailed = false
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return // A newer query replaced this one.
        }
        searching = true
        defer { searching = false }
        do {
            let found = try await panel.messageCandidates(matching: query)
            guard !Task.isCancelled else { return }
            candidates = found.filter { !panel.isOwnAccount(handle: "@\($0.handle)") }
            searchFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            Log.feed.error("New message search failed: \(error)")
            candidates = []
            searchFailed = true
        }
    }

    private func open(_ candidate: MentionCandidate) {
        opening = candidate.handle
        openError = nil
        openTask = Task {
            defer { opening = nil }
            do {
                let convo = try await panel.conversation(with: candidate.handle)
                guard !Task.isCancelled else { return } // Cancelled or dismissed meanwhile.
                onOpen(convo)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                openError = "Couldn't start a conversation with @\(candidate.handle). \(error.userMessage)"
            }
        }
    }
}
