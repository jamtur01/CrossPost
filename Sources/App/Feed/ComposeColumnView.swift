import SwiftUI

struct ComposeColumnView: View {
    @EnvironmentObject var store: AccountStore
    @State private var model: ComposeModel?

    var body: some View {
        Group {
            if let model { content(model) } else { Color.clear.onAppear { model = ComposeModel(store: store) } }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func content(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        // Effective limit = the strictest selected target. Bluesky's 300 is always
        // the floor when selected; otherwise use the connected instance's limit.
        let limit = model.selectedTargets.contains(.bluesky)
            ? TargetLimits.blueskyMax : store.mastodonMaxChars
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("New Post").font(Theme.columnTitle)
                Spacer()
            }
            .padding(.horizontal, Theme.headerPaddingH)
            .frame(height: 40)
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
                            limit: limit,
                            showLabel: !isSinglePost,
                            canRemove: !isSinglePost,
                            onRemove: { model.removePost(at: index) },
                            onPreparedAttachments: { id, result in
                                _ = model.applyPreparedAttachments(result, to: id)
                            }
                        )
                    }
                    addThreadButton(model)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            footer(model)
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
                Spacer(minLength: 0)
                ForEach(PostTarget.allCases) { target in
                    let selected = model.selectedTargets.contains(target)
                    targetPill(
                        target,
                        selected: selected,
                        posted: !selected && model.isLocked(target)
                    ) {
                        model.toggle(target)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                if model.selectedTargets.contains(.mastodon) {
                    Image(systemName: PostTarget.mastodon.glyph)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    VisibilityMenu(
                        visibility: $model.visibility,
                        accent: PostTarget.mastodon.accent
                    )
                }

                Spacer()

                Button { Task { await model.submit() } } label: {
                    Text(model.isPosting ? "Posting…" : "Post")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canPost)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .barSurface(divider: .top)
    }

    @ViewBuilder
    private func validationErrors(_ model: ComposeModel) -> some View {
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

    private func targetPill(_ target: PostTarget, selected: Bool, posted: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: posted ? "checkmark.circle.fill" : target.glyph)
                    .font(.system(size: 12))
                Text(target.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .lineLimit(1)
            .fixedSize()
            .opacity(posted ? 0.55 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? target.accent : .secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? target.accent.opacity(0.10) : Theme.hoverFill))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        selected ? target.accent.opacity(0.30) : Theme.hairline,
                        lineWidth: 0.75
                    ))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: selected)
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
