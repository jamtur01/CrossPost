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
        VStack(alignment: .leading, spacing: 8) {
            Text("New Post").font(.headline)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($model.thread) { $post in
                        let index = model.thread.firstIndex(where: { $0.id == post.id }) ?? 0
                        PostCardView(post: $post, index: index,
                                     canRemove: model.thread.count > 1,
                                     onRemove: { model.removePost(at: index) })
                    }
                    Button { model.addPost() } label: {
                        Label("Add post to thread", systemImage: "plus")
                    }
                    .buttonStyle(.borderless).font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let issues = model.blockedIssues, !issues.isEmpty {
                Text("Too long or empty — fix before posting.").font(.caption).foregroundStyle(.red)
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }

            Divider()
            HStack(spacing: 6) {
                ForEach(PostTarget.allCases) { target in
                    Toggle(target.displayName, isOn: Binding(
                        get: { model.selectedTargets.contains(target) },
                        set: { _ in model.toggle(target) }))
                    .toggleStyle(.button).controlSize(.small)
                }
                Spacer()
                Button(model.isPosting ? "Posting…" : "Post") { Task { await model.submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canPost)
            }
        }
        .padding(12)
    }
}
