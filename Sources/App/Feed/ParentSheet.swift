import SwiftUI

/// Shows the post a reply is replying to, fetched on demand.
struct ParentSheet: View {
    let fetch: () async -> FeedPost?
    let onOpen: (FeedPost) -> Void
    let onClose: () -> Void

    @State private var parent: FeedPost?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("In reply to").font(.headline)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 90)
            } else if let parent {
                FeedPostView(post: parent, showActions: false)
                HStack {
                    Spacer()
                    Button { onOpen(parent) } label: {
                        Label("Open in browser", systemImage: "safari")
                    }
                    .buttonStyle(.borderless).font(.callout)
                }
            } else {
                Label("The original post couldn't be loaded (it may be deleted or private).",
                      systemImage: "questionmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task {
            parent = await fetch()
            loading = false
        }
    }
}
