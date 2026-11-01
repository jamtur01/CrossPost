import AppKit
import SwiftUI

struct ComposeColumnView: View {
    @EnvironmentObject var store: AccountStore
    @Bindable var model: ComposeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingNewDraft = false

    var body: some View {
        content(model)
            .background(Color(nsColor: .windowBackgroundColor))
            .sheet(item: $model.pairing) { request in
                MentionPairSheet(request: request, model: model)
            }
            .confirmationDialog("Discard this draft and start a new one?", isPresented: $confirmingNewDraft) {
                Button("Discard Draft", role: .destructive) { model.startNewDraft() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Published posts stay on their networks. This discards the saved draft and its retry history.")
            }
    }

    @ViewBuilder
    private func content(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header(model)
                .padding(.horizontal, Theme.headerPaddingH)
                .frame(height: 52)
                .barSurface()

            ScrollView {
                VStack(spacing: 12) {
                    let isSinglePost = model.thread.count == 1
                    let indexByID = Dictionary(
                        uniqueKeysWithValues: model.thread.enumerated().map { ($1.id, $0) }
                    )
                    ForEach($model.thread) { $post in
                        let index = threadIndex(of: post.id, in: indexByID)
                        PostCardView(
                            post: $post,
                            index: index,
                            counters: model.counters(for: post),
                            placeholder: model.editorPlaceholder,
                            preview: model.previewTarget.map {
                                PostPreview(target: $0, parts: post.renderedParts(for: $0))
                            },
                            mentionEditing: MentionEditing(
                                completion: model.mentionCompletion(for: post.id),
                                requestPairing: { span, target in
                                    model.pairing = MentionPairingRequest(draftID: post.id, span: span,
                                                                          target: target)
                                }
                            ),
                            showLabel: !isSinglePost,
                            canRemove: !isSinglePost,
                            onRemove: { model.removePost(at: index) },
                            onPreparedAttachments: { id, result in
                                _ = model.applyPreparedAttachments(result, to: id)
                            }
                        )
                    }
                    addThreadButton(model)
                    footer(model)
                    // The history yields the space as soon as the user starts writing.
                    VStack(spacing: 0) {
                        if model.isIdle {
                            RecentPostsSection(history: model.history)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isIdle)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    /// The title, with what the cards show (the draft, or one network's final text)
    /// beneath it as a menu, the same way the feed columns show their feed.
    private func header(_ model: ComposeModel) -> some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text("New Post").font(Theme.columnTitle).lineLimit(1)
                previewMenu(model)
            }
            Spacer(minLength: 8)
            draftMenu(model)
        }
    }

    /// Edit, or a selected network's final text. Disabled until a network is selected.
    private func previewMenu(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        let targets = PostTarget.allCases.filter { model.selectedTargets.contains($0) }
        let title = model.previewTarget.map { "Previewing \($0.displayName)" } ?? "Editing"
        return Menu {
            Picker("Show", selection: $model.previewTarget) {
                Text("Edit Draft").tag(PostTarget?.none)
                ForEach(targets) { target in
                    Text("Preview for \(target.displayName)").tag(PostTarget?.some(target))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 3) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(Theme.columnSubtitle)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        // Plain-styled like the feed headers' menu, so it reads as the title's subtitle.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(targets.isEmpty)
        .accessibilityLabel("Showing: \(title)")
        .accessibilityHint("Choose the draft or the text a network will receive")
        .help("Show the text each network will receive")
    }

    /// Draft actions, in the same overflow style as the feed column headers so the
    /// header fits the composer's minimum width.
    private func draftMenu(_ model: ComposeModel) -> some View {
        Menu {
            Button("New Draft…") { confirmingNewDraft = true }
                .disabled(model.isPosting)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .accessibilityLabel("Draft actions")
        .help("Draft actions")
    }

    private func addThreadButton(_ model: ComposeModel) -> some View {
        Button { model.addPost() } label: {
            Label("Add post to thread", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless).font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where the whole thread goes and how: each network's toggle with its audience,
    /// and the Post button. Flat under the last card, so the cards stay the focus.
    private func footer(_ model: ComposeModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            validationErrors(model)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    destinations(model)
                    Spacer(minLength: 0)
                    postButton(model)
                }
                VStack(alignment: .trailing, spacing: 10) {
                    destinations(model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    postButton(model)
                }
            }
            if let warning = model.audienceWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func postButton(_ model: ComposeModel) -> some View {
        Button { Task { await model.submit() } } label: {
            Text(model.submissionLabel).lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!model.canPost)
        .fixedSize()
        .help("\(model.submissionLabel) (⌘↩)")
    }

    /// One row per network: its toggle, then its audience while it's selected.
    private func destinations(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(PostTarget.allCases) { target in
                let selected = model.selectedTargets.contains(target)
                GridRow {
                    targetPill(target, selected: selected, locked: !selected && model.isLocked(target)) {
                        model.toggle(target)
                    }
                    if selected {
                        audience(target, model: model)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post to")
    }

    @ViewBuilder
    private func audience(_ target: PostTarget, model: ComposeModel) -> some View {
        @Bindable var model = model
        switch target {
        case .mastodon:
            VisibilityMenu(visibility: $model.visibility, accent: PostTarget.mastodon.accent)
        case .bluesky:
            // Bluesky has no per-post audience, so this is a fixed value, not a menu.
            Label("Public", systemImage: "globe")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()
                .help("Bluesky posts are always public")
        }
    }

    @ViewBuilder
    private func validationErrors(_ model: ComposeModel) -> some View {
        ForEach(PostTarget.allCases) { target in
            if let status = model.publicationStatus(for: target) {
                Text(status).font(.callout)
            }
        }
        if let message = model.completionMessage {
            Label(message, systemImage: "checkmark.circle")
                .font(.caption)
        }
        if let error = model.draftError {
            Text(error).font(.caption).foregroundStyle(.red)
            if let draftStore = model.draftStore {
                Button("Show saved draft") {
                    NSWorkspace.shared.activateFileViewerSelecting([draftStore.url])
                }
                .font(.caption)
            }
        }
        if let issues = model.blockedIssues, !issues.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Text(validationMessage(issue) { "Post \($0 + 1)" })
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        if let error = model.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func targetPill(_ target: PostTarget, selected: Bool, locked: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark.circle.fill" : (locked ? "lock.circle" : "circle"))
                    .font(.system(size: 12))
                Text(target.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? target.accent.opacity(0.10) : Theme.hoverFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        selected ? target.accent.opacity(0.30) : Theme.hairline,
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: selected)
        .accessibilityLabel(target.displayName)
        .accessibilityValue(selected ? "Selected" : (locked ? "Locked; select for details" : "Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(
            selected
                ? "Posting to \(target.displayName)"
                : "Not posting to \(target.displayName)"
        )
    }

    /// A draft's position in the thread. The ForEach iterates the same array the
    /// mapping was built from, so a miss means the thread mutated mid-render:
    /// flag it in debug and fall back to the first slot rather than crash.
    private func threadIndex(of id: UUID, in indexByID: [UUID: Int]) -> Int {
        guard let index = indexByID[id] else {
            assertionFailure("Draft post \(id) missing from compose thread during render")
            return 0
        }
        return index
    }
}
