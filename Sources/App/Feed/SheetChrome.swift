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
