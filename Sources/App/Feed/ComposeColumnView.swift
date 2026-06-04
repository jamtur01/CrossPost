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
        let limit = model.selectedTargets.contains(.bluesky)
            ? TargetLimits.blueskyMax : TargetLimits.mastodonFallback
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .medium))
                Text("New Post").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
            .background(.bar)

            Divider()

            if model.thread.count == 1 {
                VStack(spacing: 12) {
                    PostCardView(post: $model.thread[0], index: 0, limit: limit,
                                 showLabel: false, fills: true,
                                 canRemove: false, onRemove: {})
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
                                         onRemove: { model.removePost(at: index) })
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
                Text("Too long or empty — fix before posting.").font(.caption).foregroundStyle(.red)
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }

            HStack(spacing: 8) {
                ForEach(PostTarget.allCases) { target in
                    targetPill(target, selected: model.selectedTargets.contains(target)) {
                        model.toggle(target)
                    }
                }
                Spacer()
                Button(model.isPosting ? "Posting…" : "Post") { Task { await model.submit() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canPost)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func targetPill(_ target: PostTarget, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(target.displayName)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Capsule().fill(selected ? target.accent : Color.secondary.opacity(0.14)))
                .foregroundStyle(selected ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .help(selected ? "Posting to \(target.displayName)" : "Not posting to \(target.displayName)")
    }
}
