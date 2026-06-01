import SwiftUI

struct ComposeView: View {
    @EnvironmentObject var store: AccountStore
    @State private var model: ComposeModel?

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .onAppear { if model == nil { model = ComposeModel(store: store) } }
    }

    @ViewBuilder
    private func content(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($model.thread) { $post in
                        let index = model.thread.firstIndex(where: { $0.id == post.id }) ?? 0
                        PostCardView(post: $post, index: index,
                                     canRemove: model.thread.count > 1,
                                     onRemove: { model.removePost(at: index) })
                    }
                }
                .padding(16)
            }

            if model.blockedIssues != nil || model.errorMessage != nil {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if let issues = model.blockedIssues { blockedBanner(issues) }
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }

            Divider()
            actionBar(model)
        }
        .frame(minWidth: 540, minHeight: 480)
        .sheet(isPresented: Binding(get: { model.results != nil },
                                    set: { if !$0 { model.results = nil } })) {
            if let results = model.results {
                ResultsSheet(results: results) { model.results = nil }
            }
        }
    }

    private func actionBar(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Button {
                model.addPost()
            } label: {
                Label("Add Post", systemImage: "plus")
            }

            Spacer()

            Text("Post to:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(PostTarget.allCases) { target in
                Toggle(target.displayName, isOn: Binding(
                    get: { model.selectedTargets.contains(target) },
                    set: { _ in model.toggle(target) }))
                .toggleStyle(.button)
            }

            Button(model.isPosting ? "Posting…" : "Post") {
                Task { await model.submit() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canPost)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func blockedBanner(_ issues: [ValidationIssue]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cannot post — fix these first:").font(.caption.bold())
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                Text(describe(issue)).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func describe(_ issue: ValidationIssue) -> String {
        switch issue {
        case .empty(let i): return "Post \(i + 1) is empty."
        case .tooLong(let i, let target, let count, let limit):
            return "Post \(i + 1) is \(count)/\(limit) for \(target.displayName)."
        }
    }
}
