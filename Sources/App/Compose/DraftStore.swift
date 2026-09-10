import Foundation

struct SavedComposeDraft: Codable, Sendable {
    var thread: [DraftPost]
    var selectedTargets: Set<PostTarget>
    var visibility: PostVisibility
    var landed: [PostTarget: LandedThread]
    var pendingTargets: Set<PostTarget>
}

struct LandedThread: Codable, Sendable {
    let items: [PostedItem]
    let signatures: [PostSignature]
    let account: String
}

struct PostSignature: Codable, Equatable, Sendable {
    let text: String
    let attachmentIDs: [UUID]

    init(_ post: DraftPost) {
        text = post.text.trimmingCharacters(in: .whitespacesAndNewlines)
        attachmentIDs = post.attachments.map(\.id)
    }
}

/// Stores one active draft, including attachment bytes and safe thread-resumption references.
final class DraftStore: Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "net.kartar.crosspost.draft")

    init(url: URL) {
        self.url = url
    }

    static var application: DraftStore {
        DraftStore(url: URL.applicationSupportDirectory
            .appending(path: "CrossPost/active-draft.plist"))
    }

    func load() throws -> SavedComposeDraft? {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try PropertyListDecoder().decode(SavedComposeDraft.self, from: Data(contentsOf: url))
        }
    }

    /// Enqueue on the same actor as flush callers, before suspension, so an older
    /// autosave cannot overtake the synchronous posting/termination checkpoint.
    @MainActor
    func save(_ draft: SavedComposeDraft) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.write(draft) })
            }
        }
    }

    /// Drains older writes and durably saves the latest snapshot before posting or quitting.
    func flush(_ draft: SavedComposeDraft) throws {
        try queue.sync { try write(draft) }
    }

    private func write(_ draft: SavedComposeDraft) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(draft)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
