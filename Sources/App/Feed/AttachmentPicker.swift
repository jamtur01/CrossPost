import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The shared image decode and thumbnail pipeline for composer and reply attachments.
/// Asynchronous work returns values; the initiating view decides whether a result is
/// still current before publishing it.
enum ImageAttaching {
    /// File types the picker and drop accept (transcoded to JPEG on send).
    static let contentTypes: [UTType] = [.png, .jpeg, .heic, .tiff]

    private static let thumbnailMaxPixel = 160
    @MainActor private static let thumbnailCache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.totalCostLimit = 2 * 1_024 * 1_024
        return cache
    }()

    fileprivate struct SendableProvider: @unchecked Sendable {
        let value: NSItemProvider
    }

    fileprivate struct PreparedImage: @unchecked Sendable {
        let attachment: Attachment
        let thumbnail: CGImage?
    }

    struct PreparedResult: Sendable {
        fileprivate let images: [PreparedImage]
        let failedNames: [String]
        let unnamedFailureCount: Int
        let exceededLimit: Bool

        var attachments: [Attachment] {
            images.map(\.attachment)
        }

        init(attachments: [Attachment],
             failedNames: [String] = [],
             unnamedFailureCount: Int = 0,
             exceededLimit: Bool = false) {
            images = attachments.map {
                PreparedImage(attachment: $0, thumbnail: nil)
            }
            self.failedNames = failedNames
            self.unnamedFailureCount = unnamedFailureCount
            self.exceededLimit = exceededLimit
        }

        fileprivate init(images: [PreparedImage],
                         failedNames: [String],
                         unnamedFailureCount: Int,
                         exceededLimit: Bool) {
            self.images = images
            self.failedNames = failedNames
            self.unnamedFailureCount = unnamedFailureCount
            self.exceededLimit = exceededLimit
        }
    }

    struct Publication: Sendable {
        let attachments: [Attachment]
        let errorMessage: String?
    }

    struct FileSelection: Sendable {
        fileprivate let urls: [URL]
        fileprivate let exceededLimit: Bool
    }

    struct ProviderSelection: Sendable {
        fileprivate let providers: [SendableProvider]
        fileprivate let exceededLimit: Bool
    }

    private struct ResultBuilder {
        var images: [PreparedImage] = []
        var failedNames: [String] = []
        var unnamedFailureCount = 0

        mutating func reject(named name: String?) {
            if let name, !name.isEmpty {
                failedNames.append(name)
            } else {
                unnamedFailureCount += 1
            }
        }

        func result(exceededLimit: Bool) -> PreparedResult {
            PreparedResult(
                images: images,
                failedNames: failedNames,
                unnamedFailureCount: unnamedFailureCount,
                exceededLimit: exceededLimit
            )
        }
    }

    private enum ProviderData: Sendable {
        case loaded(Data, name: String?)
        case failed(name: String?)
    }

    /// Opens the system picker and returns only the selection metadata. No
    /// asynchronous work or publication starts here.
    @MainActor
    static func selectFiles(remainingSlots: Int) -> FileSelection? {
        guard remainingSlots > 0 else { return nil }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return nil }

        let urls = Array(panel.urls.prefix(remainingSlots))
        return FileSelection(
            urls: urls,
            exceededLimit: panel.urls.count > urls.count
        )
    }

    /// Captures the provider selection before it crosses into detached work.
    @MainActor
    static func selectProviders(_ providers: [NSItemProvider],
                                remainingSlots: Int) -> ProviderSelection {
        let selected = providers.prefix(max(0, remainingSlots)).map {
            SendableProvider(value: $0)
        }
        return ProviderSelection(
            providers: selected,
            exceededLimit: providers.count > selected.count
        )
    }

    static func prepare(_ selection: FileSelection) async -> PreparedResult? {
        await runDetached {
            prepare(urls: selection.urls, exceededLimit: selection.exceededLimit)
        }
    }

    static func prepare(_ selection: ProviderSelection) async -> PreparedResult? {
        await runDetached {
            await prepare(
                providers: selection.providers,
                exceededLimit: selection.exceededLimit
            )
        }
    }

    /// Runs expensive preparation away from the main actor and explicitly forwards
    /// cancellation to the detached child.
    static func runDetached<Value: Sendable>(
        operation: @escaping @Sendable () async -> Value
    ) async -> Value {
        let worker = Task.detached(priority: .userInitiated) {
            await operation()
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

extension ImageAttaching {

    private static func prepare(urls: [URL],
                                exceededLimit: Bool) -> PreparedResult? {
        var builder = ResultBuilder()
        builder.images.reserveCapacity(urls.count)
        for url in urls {
            guard !Task.isCancelled else { return nil }
            do {
                let data = try Data(contentsOf: url)
                guard !Task.isCancelled else { return nil }
                guard let image = prepare(data: data) else {
                    guard !Task.isCancelled else { return nil }
                    builder.reject(named: url.lastPathComponent)
                    continue
                }
                builder.images.append(image)
            } catch {
                guard !Task.isCancelled else { return nil }
                builder.reject(named: url.lastPathComponent)
            }
        }
        guard !Task.isCancelled else { return nil }
        return builder.result(exceededLimit: exceededLimit)
    }

    private static func prepare(providers: [SendableProvider],
                                exceededLimit: Bool) async -> PreparedResult? {
        var builder = ResultBuilder()
        builder.images.reserveCapacity(providers.count)
        for provider in providers {
            guard !Task.isCancelled else { return nil }
            let providerData: ProviderData
            do {
                providerData = try await data(from: provider.value)
            } catch is CancellationError {
                return nil
            } catch {
                preconditionFailure("Provider transfer failed unexpectedly: \(error)")
            }
            switch providerData {
            case .loaded(let data, let name):
                guard let image = prepare(data: data) else {
                    guard !Task.isCancelled else { return nil }
                    builder.reject(named: name)
                    continue
                }
                builder.images.append(image)
            case .failed(let name):
                builder.reject(named: name)
            }
        }
        guard !Task.isCancelled else { return nil }
        return builder.result(exceededLimit: exceededLimit)
    }

    private static func data(from provider: NSItemProvider) async throws -> ProviderData {
        try Task.checkCancellation()
        let suggestedName = provider.suggestedName
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = try await loadProviderValue { completion in
                provider.loadObject(ofClass: URL.self) { url, _ in
                    completion(url)
                }
            }
            try Task.checkCancellation()
            guard let url else { return .failed(name: suggestedName) }
            do {
                let data = try Data(contentsOf: url)
                try Task.checkCancellation()
                return .loaded(data, name: url.lastPathComponent)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .failed(name: url.lastPathComponent)
            }
        }

        guard provider.canLoadObject(ofClass: NSImage.self) else {
            return .failed(name: suggestedName)
        }
        let data: Data? = try await loadProviderValue { completion in
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { data, _ in
                completion(data)
            }
        }
        try Task.checkCancellation()
        guard let data else { return .failed(name: suggestedName) }
        return .loaded(data, name: suggestedName)
    }

    static func loadProviderValue<Value: Sendable>(
        operation: (@escaping @Sendable (Value) -> Void) -> Progress
    ) async throws -> Value {
        let transfer = ProviderTransfer<Value>()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                transfer.start(
                    continuation: continuation,
                    operation: operation
                )
            }
        } onCancel: {
            transfer.cancel()
        }
    }

    private static func prepare(data: Data) -> PreparedImage? {
        guard !Task.isCancelled else { return nil }
        let image: PreparedImage? = autoreleasepool {
            guard ImageProcessor.canDecode(data),
                  let thumbnail = ImageProcessor.thumbnail(
                    data,
                    maxPixel: thumbnailMaxPixel
                  ) else {
                return nil
            }
            return PreparedImage(
                attachment: Attachment(imageData: data),
                thumbnail: thumbnail
            )
        }
        guard !Task.isCancelled else { return nil }
        return image
    }

    /// Rechecks capacity at publication time and populates the main-actor thumbnail
    /// cache only for attachments that will actually be appended.
    @MainActor
    static func publication(for result: PreparedResult,
                            existingCount: Int) -> Publication {
        let remaining = max(0, TargetLimits.imageMax - existingCount)
        let accepted = Array(result.images.prefix(remaining))
        for image in accepted {
            guard let thumbnail = image.thumbnail else { continue }
            let rendered = NSImage(cgImage: thumbnail, size: .zero)
            let cost = thumbnail.bytesPerRow * thumbnail.height
            thumbnailCache.setObject(
                rendered,
                forKey: image.attachment.id as NSUUID,
                cost: cost
            )
        }

        let reachedLimit = result.exceededLimit || result.images.count > accepted.count
        return Publication(
            attachments: accepted.map(\.attachment),
            errorMessage: errorMessage(for: result, reachedLimit: reachedLimit)
        )
    }

    private static func errorMessage(for result: PreparedResult,
                                     reachedLimit: Bool) -> String? {
        var messages: [String] = []
        if !result.failedNames.isEmpty || result.unnamedFailureCount > 0 {
            var failures = result.failedNames.joined(separator: ", ")
            if result.unnamedFailureCount > 0 {
                let noun = result.unnamedFailureCount == 1 ? "image" : "images"
                let unnamed = "\(result.unnamedFailureCount) other \(noun)"
                failures = failures.isEmpty ? unnamed : "\(failures), \(unnamed)"
            }
            messages.append("Couldn't read \(failures).")
        }
        if reachedLimit {
            messages.append("Maximum \(TargetLimits.imageMax) images per post.")
        }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    @MainActor
    fileprivate static func thumbnail(for id: UUID) -> NSImage? {
        thumbnailCache.object(forKey: id as NSUUID)
    }

    @MainActor
    fileprivate static func removeThumbnail(for id: UUID) {
        thumbnailCache.removeObject(forKey: id as NSUUID)
    }
}

/// Horizontal thumbnail strip with a remove button and an alt-text field per image.
/// Shared by the composer card and the reply sheet.
struct AttachmentBar: View {
    @Binding var attachments: [Attachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach($attachments) { $attachment in
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            if let image = ImageAttaching.thumbnail(for: attachment.id) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .clipShape(RoundedRectangle(
                                        cornerRadius: Theme.mediaCorner,
                                        style: .continuous
                                    ))
                            }
                            Button(role: .destructive) {
                                ImageAttaching.removeThumbnail(for: attachment.id)
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.plain)
                            .help("Remove image")
                        }
                        TextField("Alt text", text: $attachment.altText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .font(.caption)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
