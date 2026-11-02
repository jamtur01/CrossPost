import SwiftUI

/// Rules shared by the account-picking sheets and Search: the shortest query worth
/// sending and how long typing must pause before it is sent.
enum AccountQuery {
    static let minLength = 2
    static let debounce = Duration.milliseconds(250)

    /// The query an account search sends: trimmed, without a leading "@".
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    }
}

/// The results area of the account-picking sheets (New Message, mention pairing):
/// the failure note, a spinner, "No accounts found.", or the scrolling `rows`.
struct AccountSearchResults<Rows: View>: View {
    let network: PostTarget
    let failed: Bool
    let searching: Bool
    let isEmpty: Bool
    /// The typed query, so "No accounts found." waits for a searchable one.
    let query: String
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        if failed {
            Text("Couldn't search \(network.displayName). Check the account in Settings.")
                .font(.callout).foregroundStyle(.secondary)
        } else if isEmpty {
            if searching {
                ProgressView().controlSize(.small)
            } else if AccountQuery.normalized(query).count >= AccountQuery.minLength {
                Text("No accounts found.").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    rows()
                }
            }
        }
    }
}
