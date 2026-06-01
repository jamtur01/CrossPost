import SwiftUI

struct ComposeColumnView: View {
    @EnvironmentObject var store: AccountStore
    @State private var model: ComposeModel?
    @State private var showThread = false

    var body: some View {
        Group {
            if let model { content(model) } else { Color.clear.onAppear { model = ComposeModel(store: store) } }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func content(_ model: ComposeModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Text("New Post").font(.headline)

            TextEditor(text: Binding(
                get: { model.thread.first?.text ?? "" },
                set: { if !model.thread.isEmpty { model.thread[0].text = $0 } }))
                .font(.body).frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                ForEach(PostTarget.allCases) { target in
                    Toggle(target.displayName, isOn: Binding(
                        get: { model.selectedTargets.contains(target) },
                        set: { _ in model.toggle(target) }))
                    .toggleStyle(.button).controlSize(.small)
                }
            }

            HStack {
                Button("Expand to thread…") { showThread = true }
                    .buttonStyle(.borderless).font(.caption)
                Spacer()
                Button(model.isPosting ? "Posting…" : "Post") { Task { await model.submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canPost)
            }

            if let issues = model.blockedIssues, !issues.isEmpty {
                Text("Too long or empty — fix before posting.").font(.caption).foregroundStyle(.red)
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            Spacer()
        }
        .padding(12)
        .sheet(isPresented: $showThread) {
            VStack(spacing: 0) {
                HStack {
                    Text("Thread").font(.headline)
                    Spacer()
                    Button("Done") { showThread = false }
                }
                .padding(12)
                Divider()
                ComposeView(model: model)
            }
            .frame(minWidth: 600, minHeight: 520)
        }
        .sheet(isPresented: Binding(
            get: { model.results != nil },
            set: { if !$0 { model.results = nil } })) {
            if let results = model.results {
                ResultsSheet(results: results) { model.results = nil }
            }
        }
    }
}
