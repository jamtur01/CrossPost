import SwiftUI
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// The one way to add and show image attachments — shared by the composer and the
/// reply sheet so both get the same file picker, drag-and-drop, paste, decode
/// validation, and thumbnail grid. Operates on a `Binding<[Attachment]>` and reports
/// user-facing problems through an `onError` sink.
enum ImageAttaching {
    /// File types the picker and drop accept (transcoded to JPEG on send).
    static let contentTypes: [UTType] = [.png, .jpeg, .heic, .tiff]

    private static let thumbnailMaxPixel = 160
    private static let thumbnailCache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.totalCostLimit = 2 * 1_024 * 1_024
        return cache
    }()

    private struct SendableProvider: @unchecked Sendable {
        let value: NSItemProvider
    }

    private struct PreparedAttachment: @unchecked Sendable {
        let attachment: Attachment
        let thumbnail: CGImage
    }

    private struct PreparedSelection: Sendable {
        var attachments: [PreparedAttachment] = []
        var failedNames: [String] = []
        var unnamedFailureCount = 0

        mutating func reject(named name: String?) {
            if let name, !name.isEmpty {
                failedNames.append(name)
            } else {
                unnamedFailureCount += 1
            }
        }
    }

    private enum ProviderData: Sendable {
        case loaded(Data, name: String?)
        case failed(name: String?)
    }

    /// Open the system file picker and append the chosen images. The remaining
    /// slot count is applied before any selected file is read.
    @MainActor
    static func pick(into attachments: Binding<[Attachment]>,
                     onError: @escaping (String) -> Void) {
        let remaining = TargetLimits.imageMax - attachments.wrappedValue.count
        guard remaining > 0 else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        let urls = Array(panel.urls.prefix(remaining))
        let exceededLimit = panel.urls.count > urls.count
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                prepare(urls: urls)
            }.value
            publish(result, exceededLimit: exceededLimit,
                    into: attachments, onError: onError)
        }
    }

    /// Load dropped or pasted image providers in their supplied order. Providers
    /// beyond the remaining slot count are never asked for data.
    @MainActor
    static func load(_ providers: [NSItemProvider],
                     into attachments: Binding<[Attachment]>,
                     onError: @escaping (String) -> Void) {
        let remaining = TargetLimits.imageMax - attachments.wrappedValue.count
        guard remaining > 0 else {
            onError("Maximum \(TargetLimits.imageMax) images per post.")
            return
        }

        let selected = providers.prefix(remaining).map { SendableProvider(value: $0) }
        let exceededLimit = providers.count > selected.count
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                await prepare(providers: selected)
            }.value
            publish(result, exceededLimit: exceededLimit,
                    into: attachments, onError: onError)
        }
    }

    private static func prepare(urls: [URL]) -> PreparedSelection {
        var result = PreparedSelection()
        result.attachments.reserveCapacity(urls.count)
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                guard let attachment = prepare(data: data) else {
                    result.reject(named: url.lastPathComponent)
                    continue
                }
                result.attachments.append(attachment)
            } catch {
                result.reject(named: url.lastPathComponent)
            }
        }
        return result
    }

    private static func prepare(providers: [SendableProvider]) async -> PreparedSelection {
        var result = PreparedSelection()
        result.attachments.reserveCapacity(providers.count)
        for provider in providers {
            switch await data(from: provider.value) {
            case .loaded(let data, let name):
                guard let attachment = prepare(data: data) else {
                    result.reject(named: name)
                    continue
                }
                result.attachments.append(attachment)
            case .failed(let name):
                result.reject(named: name)
            }
        }
        return result
    }

    private static func data(from provider: NSItemProvider) async -> ProviderData {
        let suggestedName = provider.suggestedName
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            guard let url else { return .failed(name: suggestedName) }
            do {
                return .loaded(try Data(contentsOf: url), name: url.lastPathComponent)
            } catch {
                return .failed(name: url.lastPathComponent)
            }
        }

        guard provider.canLoadObject(ofClass: NSImage.self) else {
            return .failed(name: suggestedName)
        }
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return .failed(name: suggestedName) }
        return .loaded(data, name: suggestedName)
    }

    private static func prepare(data: Data) -> PreparedAttachment? {
        autoreleasepool {
            guard ImageProcessor.canDecode(data),
                  let thumbnail = ImageProcessor.thumbnail(data, maxPixel: thumbnailMaxPixel) else {
                return nil
            }
            return PreparedAttachment(
                attachment: Attachment(imageData: data),
                thumbnail: thumbnail
            )
        }
    }

    @MainActor
    private static func publish(_ result: PreparedSelection,
                                exceededLimit: Bool,
                                into attachments: Binding<[Attachment]>,
                                onError: (String) -> Void) {
        let remaining = max(0, TargetLimits.imageMax - attachments.wrappedValue.count)
        let accepted = result.attachments.prefix(remaining)
        for item in accepted {
            let image = NSImage(cgImage: item.thumbnail, size: .zero)
            let cost = item.thumbnail.bytesPerRow * item.thumbnail.height
            thumbnailCache.setObject(image, forKey: item.attachment.id as NSUUID, cost: cost)
            attachments.wrappedValue.append(item.attachment)
        }

        let reachedLimit = exceededLimit || result.attachments.count > accepted.count
        if let message = errorMessage(for: result, reachedLimit: reachedLimit) {
            onError(message)
        }
    }

    private static func errorMessage(for result: PreparedSelection,
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
    fileprivate static func thumbnail(for id: UUID) -> NSImage? {
        thumbnailCache.object(forKey: id as NSUUID)
    }
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
