import SwiftUI

extension View {
    /// Standard sheet sizing used by all compose/action sheets.
    func sheetContainer() -> some View {
        padding(20).frame(width: Theme.sheetWidth)
    }
}

/// The header row for a sheet: an accent dot (no icon) or an accent SF Symbol,
/// followed by the title.
@ViewBuilder
func sheetHeader(icon: String?, label: String, accent: Color) -> some View {
    HStack(spacing: 8) {
        if let icon {
            Image(systemName: icon).foregroundStyle(accent)
        } else {
            Circle().fill(accent).frame(width: 9, height: 9)
        }
        Text(label).font(Theme.columnTitle)
    }
}

/// The shared footer row for compose/action sheets: an optional success label, a
/// Cancel button (Esc), and a prominent submit button (⌘↩) that shows a progress
/// verb while sending. Cancel is disabled while sending or once sent; submit is
/// disabled by that plus the caller's `canSubmit`. Purely presentational — the
/// caller's `onSubmit` still owns the send/sent/dismiss flow.
struct SheetFooter: View {
    let sending: Bool
    let sent: Bool
    let successLabel: String
    let submitLabel: String
    let submittingLabel: String
    var role: ButtonRole?
    var canSubmit: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack {
            if sent {
                Label(successLabel, systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(sending || sent)
            Button(sending ? submittingLabel : submitLabel, role: role, action: onSubmit)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSubmit || sending || sent)
        }
    }
}
