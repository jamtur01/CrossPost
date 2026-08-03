import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PostCardView: View {
    @Binding var post: DraftPost
    let index: Int
    let limit: Int
    var showLabel: Bool = true   // "Post N" + remove (thread mode)
    let canRemove: Bool
    let onRemove: () -> Void
    let onPreparedAttachments: (UUID, ImageAttaching.PreparedResult) -> Void

    @State private var isDropTarget = false
    @State private var attachmentPreparation = AttachmentPreparationOwner()

    private var count: Int { PostValidator.graphemeCount(post.text) }
    private var canAddImages: Bool { post.attachments.count < TargetLimits.imageMax }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showLabel {
                HStack {
                    Text("Post \(index + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if canRemove {
                        Button(role: .destructive) {
                            attachmentPreparation.cancel()
                            onRemove()
                        } label: {
                            Image(systemName: "trash").font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this post")
                    }
                }
            }

            editor

            if !post.attachments.isEmpty { AttachmentBar(attachments: $post.attachments) }

            HStack(spacing: 12) {
                Button(action: chooseFiles) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(!canAddImages)
                .help(canAddImages ? "Add image" : "Maximum \(TargetLimits.imageMax) images")

                Spacer()

                Text("\(count)/\(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(counterColor(count: count, limit: limit))
            }
        }
        .padding(14)
        .cardSurface()
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                            .fill(Color.accentColor.opacity(0.06)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTarget) { providers in
            prepare(providers)
            return true
        }
        .onPasteCommand(of: [.image, .fileURL], perform: prepare)
        .onChange(of: post.id) {
            attachmentPreparation.cancel()
        }
        .onDisappear {
            attachmentPreparation.cancel()
        }
    }

    private func chooseFiles() {
        guard let selection = ImageAttaching.selectFiles(
            remainingSlots: TargetLimits.imageMax - post.attachments.count
        ) else {
            return
        }
        let draftID = post.id
        attachmentPreparation.start(
            operation: { await ImageAttaching.prepare(selection) },
            onPrepared: { result in
                onPreparedAttachments(draftID, result)
            }
        )
    }

    private func prepare(_ providers: [NSItemProvider]) {
        let selection = ImageAttaching.selectProviders(
            providers,
            remainingSlots: TargetLimits.imageMax - post.attachments.count
        )
        let draftID = post.id
        attachmentPreparation.start(
            operation: { await ImageAttaching.prepare(selection) },
            onPrepared: { result in
                onPreparedAttachments(draftID, result)
            }
        )
    }

    private var editor: some View {
        PlainTextEditor(text: $post.text)
            .frame(minHeight: 90, maxHeight: 200)
            .overlay(alignment: .topLeading) {
                if post.text.isEmpty {
                    Text("What's on your mind?")
                        .font(Theme.content).foregroundStyle(.tertiary)
                        .padding(.leading, 5).padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Owns one preparation generation. Replacing or canceling work releases its
/// publication closure immediately and prevents a late detached result from applying.
@MainActor
final class AttachmentPreparationOwner {
    typealias Operation = @Sendable () async -> ImageAttaching.PreparedResult?
    typealias Completion = @MainActor (ImageAttaching.PreparedResult) -> Void

    private var task: Task<Void, Never>?
    private var generation: UInt = 0
    private var completion: Completion?

    @discardableResult
    func start(operation: @escaping Operation,
               onPrepared: @escaping Completion) -> Task<Void, Never> {
        cancel()
        let startedGeneration = generation
        completion = onPrepared
        let task = Task { [weak self] in
            let result = await operation()
            guard !Task.isCancelled else {
                self?.finish(nil, generation: startedGeneration)
                return
            }
            self?.finish(result, generation: startedGeneration)
        }
        self.task = task
        return task
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        completion = nil
    }

    private func finish(_ result: ImageAttaching.PreparedResult?,
                        generation startedGeneration: UInt) {
        guard generation == startedGeneration else { return }
        task = nil
        let completion = completion
        self.completion = nil
        guard let result else { return }
        completion?(result)
    }

    deinit {
        task?.cancel()
    }
}
