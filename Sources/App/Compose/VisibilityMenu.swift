import SwiftUI

/// A compact menu for choosing Mastodon post visibility. Only meaningful for
/// Mastodon, so callers show it only when Mastodon is a target.
struct VisibilityMenu: View {
    @Binding var visibility: PostVisibility
    var accent: Color = .accentColor

    var body: some View {
        Menu {
            Picker("Visibility", selection: $visibility) {
                ForEach(PostVisibility.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(visibility.title, systemImage: visibility.symbol)
                .font(.system(size: 12.5, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .tint(accent)
        .fixedSize()
        .help("Mastodon visibility — \(visibility.detail)")
    }
}
