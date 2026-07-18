import SwiftUI

// Helpers shared by the compose column and the feed action sheets
// (reply/edit/quote/report), so limits, timing, and editor chrome stay in sync.

/// Warn (orange) once within this many graphemes of the limit.
private let counterWarnWithin = 20

/// Character-counter color shared by every composer surface: red over the
/// limit, orange when close, secondary otherwise.
func counterColor(count: Int, limit: Int) -> Color {
    if count > limit { return .red }
    if count >= limit - counterWarnWithin { return .orange }
    return .secondary
}

/// The bordered text editor used by the action sheets: rounded text-background
/// fill, quaternary stroke, and an optional placeholder shown while empty.
struct SheetTextEditor: View {
    @Binding var text: String
    let minHeight: CGFloat
    var placeholder: String?

    var body: some View {
        PlainTextEditor(text: $text)
            .frame(minHeight: minHeight)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(alignment: .topLeading) {
                if let placeholder, text.isEmpty {
                    Text(placeholder)
                        .font(Theme.content).foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

/// Holds the sheet open briefly so the success state registers, then dismisses.
/// The single home of the 800ms sent-flash every action sheet uses.
@MainActor
func flashSentThenClose(onClose: () -> Void) async {
    try? await Task.sleep(nanoseconds: 800_000_000)
    onClose()
}

/// The shared submit flow for action sheets: mark sending, run the operation,
/// flash the success state, then dismiss. On failure the error lands in
/// `errorMessage` and the sheet stays open for another attempt.
@MainActor
func submitSheet(isSending: Binding<Bool>, sent: Binding<Bool>, errorMessage: Binding<String?>,
                 onClose: @escaping () -> Void, operation: @escaping () async throws -> Void) {
    isSending.wrappedValue = true
    errorMessage.wrappedValue = nil
    Task {
        defer { isSending.wrappedValue = false }
        do {
            try await operation()
            sent.wrappedValue = true
            await flashSentThenClose(onClose: onClose)
        } catch {
            errorMessage.wrappedValue = error.userMessage
        }
    }
}

/// User-facing description of a validation issue. `subject` names the offending
/// post for the surface's context: the compose thread labels by index
/// ("Post 2"), a reply sheet just says "Reply".
func validationMessage(_ issue: ValidationIssue, subject: (_ postIndex: Int) -> String) -> String {
    switch issue {
    case .empty(let postIndex):
        return "\(subject(postIndex)) is empty."
    case .tooLong(let postIndex, let target, let count, let limit):
        return "\(subject(postIndex)) is too long for \(target.displayName): \(count)/\(limit)."
    case .tooLongBytes(let postIndex, let target, let count, let limit):
        return "\(subject(postIndex)) is too long for \(target.displayName): \(count)/\(limit) bytes."
    case .tooManyImages(let postIndex, let target, let count, let limit):
        return "\(subject(postIndex)) has too many images for \(target.displayName): \(count)/\(limit)."
    case .altTextTooLong(let postIndex, let imageIndex, let target, let count, let limit):
        return "\(subject(postIndex)) image \(imageIndex + 1) alt text is too long for "
            + "\(target.displayName): \(count)/\(limit)."
    }
}
