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
            .padding(.horizontal, Theme.headerPaddingH).padding(.top, 10).padding(.bottom, 9)
            .background(.bar)

            Divider()

            if model.thread.count == 1 {
                VStack(spacing: 12) {
                    PostCardView(post: $model.thread[0], index: 0, limit: limit,
                                 showLabel: false, fills: true,
                                 canRemove: false, onRemove: {},
                                 onError: { model.errorMessage = $0 })
                        .frame(maxHeight: .infinity)
                    addThreadButton(model)
                }
                .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($model.thread) { $post in
                            let index = model.thread.firstIndex(where: { $0.id == post.id }) ?? 0
                            PostCardView(post: $post, index: index, limit: limit,
                                         canRemove: true,
                                         onRemove: { model.removePost(at: index) },
                                         onError: { model.errorMessage = $0 })
                        }
                        addThreadButton(model)
                    }
                    .padding(14)
                }
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
            if let issues = model.blockedIssues, !issues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text(validationMessage(issue))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if model.selectedTargets.contains(.mastodon) {
                HStack(spacing: 6) {
                    Image(systemName: PostTarget.mastodon.glyph)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    VisibilityMenu(visibility: $model.visibility, accent: PostTarget.mastodon.accent)
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(PostTarget.allCases) { target in
                    let selected = model.selectedTargets.contains(target)
                    targetPill(target, selected: selected, posted: !selected && model.isLocked(target)) {
                        model.toggle(target)
                    }
                }
                Spacer(minLength: 0)
            }

            Button { Task { await model.submit() } } label: {
                Text(model.isPosting ? "Posting…" : "Post")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canPost)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .barSurface(divider: .top)
    }

    private func targetPill(_ target: PostTarget, selected: Bool, posted: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: posted ? "checkmark.circle.fill" : target.glyph).font(.system(size: 12))
                Text(target.displayName).font(.system(size: 12.5, weight: .medium))
            }
            .lineLimit(1)
            .fixedSize()
            .opacity(posted ? 0.55 : 1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(selected ? target.accent : .secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? target.accent.opacity(0.14) : Color.primary.opacity(0.05)))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? target.accent.opacity(0.45) : Color.primary.opacity(0.08),
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: selected)
        .help(selected ? "Posting to \(target.displayName)" : "Not posting to \(target.displayName)")
    }

    private func validationMessage(_ issue: ValidationIssue) -> String {
        switch issue {
        case .empty(let postIndex):
            return "Post \(postIndex + 1) is empty."
        case .tooLong(let postIndex, let target, let count, let limit):
            return "Post \(postIndex + 1) is too long for \(target.displayName): \(count)/\(limit)."
        case .tooLongBytes(let postIndex, let target, let count, let limit):
            return "Post \(postIndex + 1) is too long for \(target.displayName): \(count)/\(limit) bytes."
        case .tooManyImages(let postIndex, let target, let count, let limit):
            return "Post \(postIndex + 1) has too many images for \(target.displayName): \(count)/\(limit)."
        case .altTextTooLong(let postIndex, let imageIndex, let target, let count, let limit):
            return "Post \(postIndex + 1) image \(imageIndex + 1) alt text is too long for "
                + "\(target.displayName): \(count)/\(limit)."
        }
    }
}
