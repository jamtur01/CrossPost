import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The one way to add and show image attachments — shared by the composer and the
/// reply sheet so both get the same file picker, drag-and-drop, paste, decode
/// validation, and thumbnail grid. Operates on a `Binding<[Attachment]>` and reports
/// user-facing problems through an `onError` sink.
enum ImageAttaching {
    /// File types the picker and drop accept (transcoded to JPEG on send).
    static let contentTypes: [UTType] = [.png, .jpeg, .heic, .tiff]

    /// Open the system file picker and append the chosen images.
    static func pick(into attachments: Binding<[Attachment]>, onError: @escaping (String) -> Void) {
        guard attachments.wrappedValue.count < TargetLimits.imageMax else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var datas: [Data] = []
        var failed: [String] = []
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) { datas.append(data) }
            else { failed.append(url.lastPathComponent) }
        }
        append(datas, into: attachments, onError: onError)
        if !failed.isEmpty { onError("Couldn't read \(failed.joined(separator: ", ")).") }
    }

    /// Append decodable images up to the per-post limit, rejecting undecodable data
    /// and over-limit drops with a message instead of dropping them silently.
    static func append(_ datas: [Data], into attachments: Binding<[Attachment]>,
                       onError: @escaping (String) -> Void) {
        guard !datas.isEmpty else { return }
        let remaining = TargetLimits.imageMax - attachments.wrappedValue.count
        guard remaining > 0 else {
            onError("Maximum \(TargetLimits.imageMax) images per post.")
            return
        }
        var added = 0
        var rejected = false
        for data in datas where added < remaining {
            if ImageProcessor.canDecode(data) {
                attachments.wrappedValue.append(Attachment(imageData: data))
                added += 1
            } else {
                rejected = true
            }
        }
        if rejected { onError("That image couldn't be read.") }
        else if datas.count > remaining { onError("Maximum \(TargetLimits.imageMax) images per post.") }
    }

    /// Load images dropped or pasted as item providers (Finder file URLs, or raw
    /// image data from a browser/Photos), appending each as it resolves.
    @MainActor
    static func load(_ providers: [NSItemProvider], into attachments: Binding<[Attachment]>,
                     onError: @escaping (String) -> Void) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let data = try? Data(contentsOf: url) else { return }
                    Task { @MainActor in append([data], into: attachments, onError: onError) }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in append([data], into: attachments, onError: onError) }
                }
            }
        }
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
                            if let img = NSImage(data: attachment.imageData) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.mediaCorner, style: .continuous))
                            }
                            Button(role: .destructive) {
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
