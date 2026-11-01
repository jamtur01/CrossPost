import SwiftUI

/// The list of DM conversations for a platform.
struct MessagesListView: View {
    let model: FeedPanelModel
    let push: (FeedRoute) -> Void

    var body: some View {
        if model.conversations.isEmpty, model.isLoading {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if let error = model.errorMessage, model.conversations.isEmpty {
            // The model exposes only user-facing error text, not the underlying
            // error kind, so the real failure is shown and the most common Bluesky
            // DM failure (an app password without DM scope) rides along as
            // secondary guidance rather than being asserted as the cause.
            VStack(spacing: 0) {
                EmptyStateView(text: error, systemImage: "exclamationmark.bubble", fills: false) {
                    model.refresh()
                }
                if model.target == .bluesky {
                    Text("If this is an authorization problem: Bluesky DMs need an app "
                        + "password with Direct Messages access — in Bluesky go to Settings "
                        + "→ App Passwords and create one with \"Allow access to your "
                        + "direct messages\" checked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.conversations.isEmpty {
            emptyState("bubble.left.and.bubble.right", "No conversations yet")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.conversations) { convo in
                        ConversationRow(convo: convo, accent: model.target.accent, push: push)
                        Divider().opacity(0.5)
                    }
                }
                .scrollTargetLayout()
                .overlayScrollers()
            }
            .scrollContentBackground(.hidden)
            .keyboardListNavigation(ids: model.conversations.map(\.id)) { id in
                model.conversations.first { $0.id == id }.map { push(.conversation($0)) }
            }
        }
    }

    private func emptyState(_ symbol: String, _ text: String) -> some View {
        EmptyStateView(text: text, systemImage: symbol)
    }
}

/// One conversation in the list: the other person, the last message, and an unread dot.
private struct ConversationRow: View {
    let convo: Conversation
    let accent: Color
    let push: (FeedRoute) -> Void

    @Environment(\.selectKeyboardRow) private var selectKeyboardRow

    var body: some View {
        Button {
            // The opened row keeps the list's keyboard focus for when Back returns.
            selectKeyboardRow?(convo.id)
            push(.conversation(convo))
        } label: {
            HStack(spacing: Theme.gutter) {
                AvatarView(url: convo.otherAvatarURL, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(convo.otherName).font(Theme.name).lineLimit(1)
                        Spacer()
                        if let date = convo.lastDate {
                            relativeTimestamp(date)
                        }
                    }
                    Text(convo.lastMessage ?? "")
                        .font(Theme.handle)
                        .foregroundStyle(convo.unreadCount > 0 ? .primary : .secondary)
                        .lineLimit(2)
                }
                if convo.unreadCount > 0 {
                    Circle().fill(accent).frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, Theme.rowPaddingH).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardFocusIndicator(id: convo.id)
    }
}

/// A single conversation: message bubbles plus a composer.
struct ConversationView: View {
    let panel: FeedPanelModel
    let conversation: Conversation
    let push: (FeedRoute) -> Void

    @State private var model: ConversationModel
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FeedKeyboardFocus.self) private var keyboardFocus: FeedKeyboardFocus?

    init(
        panel: FeedPanelModel,
        conversation: Conversation,
        push: @escaping (FeedRoute) -> Void
    ) {
        self.panel = panel
        self.conversation = conversation
        self.push = push
        _model = State(initialValue: ConversationModel(panel: panel, conversation: conversation))
    }

    private var accent: Color {
        panel.target.accent
    }

    private var otherProfile: ProfileRef {
        ProfileRef(
            id: conversation.otherID,
            handle: conversation.otherHandle,
            name: conversation.otherName,
            avatar: conversation.otherAvatarURL
        )
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if model.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        if let loadError = model.loadError {
                            ErrorStateView(message: loadError, fills: false) {
                                model.reload()
                            }
                        }
                        ForEach(model.messages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlayScrollers()
                }
                .scrollContentBackground(.hidden)
                // The conversation takes the keyboard when opened; Return moves it to
                // the message field (with or without messages), and Esc there brings it back.
                .keyboardListNavigation(ids: model.messages.map(\.id),
                                        initialSelection: model.messages.last?.id,
                                        openWithoutSelection: focusMessageField) { _ in
                    focusMessageField()
                }
                .onChange(of: model.messages.last?.id) {
                    if let last = model.messages.last {
                        withAnimation(reduceMotion ? nil : .default) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            composer(draft: $model.draft)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            panel.markConversationRead(conversation.id)
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    /// Return writes a message, so the keyboard stays in this view: take back the
    /// hand-off the list makes for a pushed route, then focus the field.
    private func focusMessageField() {
        _ = keyboardFocus?.claim(panel.target)
        fieldFocused = true
    }

    /// Tappable header opening the other participant's profile.
    private var header: some View {
        Button { push(.profile(otherProfile)) } label: {
            HStack(spacing: 8) {
                AvatarView(url: conversation.otherAvatarURL, size: 30, ring: false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(conversation.otherName)
                        .font(Theme.name)
                        .lineLimit(1)
                    Text(conversation.otherHandle)
                        .font(Theme.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .barSurface()
    }

    private func bubble(_ message: DirectMessage) -> some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
            Text(message.text)
                .readingFont()
                .foregroundStyle(message.isFromMe ? .white : .primary)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    message.isFromMe ? panel.target.fillAccent : Color.secondary.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: Theme.bubbleCorner, style: .continuous)
                )
                .frame(maxWidth: 260, alignment: message.isFromMe ? .trailing : .leading)
            Text(message.date, format: .dateTime.hour().minute())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
        // The ring sits just outside the bubble rather than over its edge.
        .padding(6)
        .keyboardFocusIndicator(id: message.id)
        .padding(-6)
    }

    private func composer(draft: Binding<String>) -> some View {
        VStack(spacing: 0) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
            HStack(spacing: 8) {
                TextField("Message", text: draft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous)
                    )
                    .focused($fieldFocused)
                    .onSubmit { model.send() }
                    .onExitCommand { keyboardFocus?.request(panel.target) }
                    .disabled(model.isSending)

                Button { model.send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .accessibilityLabel("Send message")
                .disabled(
                    model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isSending
                )
            }
            .padding(10)
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
