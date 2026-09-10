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
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("New Post").font(Theme.columnTitle)
                Spacer()
                Button("New draft…") { confirmingNewDraft = true }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(model.isPosting)
            }
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
                            limit: model.characterLimit,
                            limitLabel: model.limitingNetwork,
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
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func addThreadButton(_ model: ComposeModel) -> some View {
        Button { model.addPost() } label: {
            Label("Add post to thread", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless).font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func footer(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            validationErrors(model)

            HStack(spacing: 8) {
                Text("Post to").font(.callout.weight(.medium))
                ForEach(PostTarget.allCases) { target in
                    let selected = model.selectedTargets.contains(target)
                    targetPill(
                        target,
                        selected: selected,
                        locked: !selected && model.isLocked(target)
                    ) {
                        model.toggle(target)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                audiences(model)

                Spacer()

                Button { Task { await model.submit() } } label: {
                    Text(model.submissionLabel)
                        .frame(minWidth: 78)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canPost)
            }
            if let warning = model.audienceWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func audiences(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 6) {
            if model.selectedTargets.contains(.mastodon) {
                HStack(spacing: 4) {
                    Text("Mastodon:")
                    VisibilityMenu(visibility: $model.visibility, accent: PostTarget.mastodon.accent)
                }
            }
            if model.selectedTargets.contains(.bluesky) {
                Label("Bluesky: Public", systemImage: "globe")
            }
        }
        .font(.caption)
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
