import SwiftUI

/// The list of DM conversations for a platform.
struct MessagesListView: View {
    let model: FeedPanelModel
    let push: (FeedRoute) -> Void

    var body: some View {
        if model.conversations.isEmpty && model.isLoading {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if model.errorMessage != nil, model.conversations.isEmpty {
            emptyState("exclamationmark.bubble",
                       "Couldn't load messages. Bluesky DMs need an app password with "
                       + "Direct Messages access — in Bluesky go to Settings → App Passwords "
                       + "and create one with \"Allow access to your direct messages\" checked.")
        } else if model.conversations.isEmpty {
            emptyState("bubble.left.and.bubble.right", "No conversations yet")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.conversations) { convo in
                        row(convo)
                        Divider().opacity(0.5)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyState(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private func row(_ convo: Conversation) -> some View {
        Button { push(.conversation(convo)) } label: {
            HStack(spacing: Theme.gutter) {
                AsyncImage(url: convo.otherAvatarURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.avatarRing, lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(convo.otherName).font(Theme.name).lineLimit(1)
                        Spacer()
                        if let date = convo.lastDate {
                            Text(date, format: .relative(presentation: .numeric))
                                .font(Theme.meta).foregroundStyle(.tertiary).fixedSize()
                        }
                    }
                    Text(convo.lastMessage ?? "")
                        .font(Theme.handle)
                        .foregroundStyle(convo.unreadCount > 0 ? .primary : .secondary)
                        .lineLimit(2)
                }
                if convo.unreadCount > 0 {
                    Circle().fill(.blue).frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, Theme.rowPaddingH).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A single conversation: message bubbles plus a composer.
struct ConversationView: View {
    let panel: FeedPanelModel
    let conversation: Conversation
    let push: (FeedRoute) -> Void

    @State private var messages: [DirectMessage] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var sending = false
    @State private var sendError: String?

    private var accent: Color { panel.target.accent }

    private var otherProfile: ProfileRef {
        ProfileRef(id: conversation.otherID, handle: conversation.otherHandle,
                   name: conversation.otherName, avatar: conversation.otherAvatarURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if loading {
                            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding()
                        }
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: messages.last?.id) {
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            composer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            panel.markConversationRead(conversation.id)
            await reload()
        }
    }

    /// Tappable header opening the other participant's profile.
    private var header: some View {
        Button { push(.profile(otherProfile)) } label: {
            HStack(spacing: 8) {
                AsyncImage(url: conversation.otherAvatarURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(conversation.otherName).font(Theme.name).lineLimit(1)
                    Text(conversation.otherHandle).font(Theme.meta).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func bubble(_ message: DirectMessage) -> some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
            Text(message.text)
                .font(Theme.content)
                .foregroundStyle(message.isFromMe ? .white : .primary)
                .textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(message.isFromMe ? accent : Color.secondary.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .frame(maxWidth: 260, alignment: .leading)
            Text(message.date, format: .dateTime.hour().minute())
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let sendError {
                Text(sendError)
                    .font(.caption).foregroundStyle(.red).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 6)
            }
            HStack(spacing: 8) {
                TextField("Message", text: $draft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit { Task { await send() } }

                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
            .padding(10)
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func reload() async {
        messages = await panel.messages(in: conversation.id)
        loading = false
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        draft = ""
        defer { sending = false }
        do {
            try await panel.sendMessage(text, to: conversation.id)
            await reload()
            await panel.reloadConversations()
        } catch {
            draft = text   // restore the text so it isn't lost
            sendError = error.userMessage
        }
    }
}
