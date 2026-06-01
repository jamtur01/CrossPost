import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AccountStore
    @State private var mastodonToken: String = ""
    @State private var blueskyPassword: String = ""
    @State private var status: String = ""
    @State private var statusIsError: Bool = false

    var body: some View {
        Form {
            Section("Mastodon") {
                TextField("Instance URL", text: $store.mastodonInstanceURL)
                    .textContentType(.URL)
                SecureField("Access token", text: $mastodonToken)
                verifyButton(title: "Verify & Save Mastodon", ready: mastodonReady) {
                    await verifyMastodon()
                }
            }

            Section("Bluesky") {
                TextField("Handle (e.g. you.bsky.social)", text: $store.blueskyHandle)
                SecureField("App password", text: $blueskyPassword)
                verifyButton(title: "Verify & Save Bluesky", ready: blueskyReady) {
                    await verifyBluesky()
                }
            }

            if !status.isEmpty {
                Section {
                    Label {
                        Text(status).font(.callout)
                    } icon: {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill"
                                                         : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .orange : .green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 12)
        .frame(width: 480)
        .onAppear {
            mastodonToken = store.mastodonToken
            blueskyPassword = store.blueskyAppPassword
        }
    }

    @ViewBuilder
    private func verifyButton(title: String, ready: Bool,
                              action: @escaping () async -> Void) -> some View {
        let button = Button(title) { Task { await action() } }
            .disabled(!ready)
        if ready {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var mastodonReady: Bool {
        !store.mastodonInstanceURL.isEmpty && !mastodonToken.isEmpty
    }

    private var blueskyReady: Bool {
        !store.blueskyHandle.isEmpty && !blueskyPassword.isEmpty
    }

    private func verifyMastodon() async {
        store.mastodonToken = mastodonToken
        do {
            _ = try await PosterFactory.makeMastodon(store)
            statusIsError = false
            status = "Mastodon verified. Max characters: \(store.mastodonMaxChars)."
        } catch {
            statusIsError = true
            status = "Mastodon error: \(error)"
        }
    }

    private func verifyBluesky() async {
        store.blueskyAppPassword = blueskyPassword
        do {
            _ = try await PosterFactory.makeBluesky(store)
            statusIsError = false
            status = "Bluesky verified for @\(store.blueskyHandle)."
        } catch {
            statusIsError = true
            status = "Bluesky error: \(error)"
        }
    }
}
