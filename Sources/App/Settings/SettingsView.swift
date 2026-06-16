import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AccountStore
    @State private var mastodonInstanceURL: String = ""
    @State private var mastodonToken: String = ""
    @State private var blueskyHandle: String = ""
    @State private var blueskyPassword: String = ""
    @State private var status: String = ""
    @State private var statusIsError: Bool = false
    @State private var verifyingMastodon = false
    @State private var verifyingBluesky = false

    var body: some View {
        Form {
            Section("Mastodon") {
                TextField("Instance URL", text: $mastodonInstanceURL)
                    .textContentType(.URL)
                SecureField("Access token", text: $mastodonToken)
                verifyButton(title: "Verify & Save Mastodon", ready: mastodonReady,
                             verifying: verifyingMastodon) {
                    await verifyMastodon()
                }
            }

            Section("Bluesky") {
                TextField("Handle (e.g. you.bsky.social)", text: $blueskyHandle)
                SecureField("App password", text: $blueskyPassword)
                verifyButton(title: "Verify & Save Bluesky", ready: blueskyReady,
                             verifying: verifyingBluesky) {
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

            Section {
                LabeledContent("Version", value: Self.appVersion)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 12)
        .frame(width: 480)
        .onAppear {
            mastodonInstanceURL = store.mastodonInstanceURL
            mastodonToken = store.mastodonToken
            blueskyHandle = store.blueskyHandle
            blueskyPassword = store.blueskyAppPassword
        }
    }

    /// Marketing version and build number from the bundle, e.g. "0.2.1 (1)".
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return build == short ? short : "\(short) (\(build))"
    }

    @ViewBuilder
    private func verifyButton(title: String, ready: Bool, verifying: Bool,
                              action: @escaping () async -> Void) -> some View {
        let button = Button { Task { await action() } } label: {
            HStack(spacing: 6) {
                if verifying { ProgressView().controlSize(.small) }
                Text(verifying ? "Verifying…" : title)
            }
        }
        .disabled(!ready || verifying)
        if ready {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var mastodonReady: Bool {
        !mastodonInstanceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !mastodonToken.isEmpty
    }

    private var blueskyReady: Bool {
        !blueskyHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !blueskyPassword.isEmpty
    }

    private func verifyMastodon() async {
        verifyingMastodon = true
        defer { verifyingMastodon = false }
        do {
            let verified = try await PosterFactory.makeMastodon(
                instanceURL: mastodonInstanceURL,
                token: mastodonToken)
            try store.saveMastodon(
                instanceURL: mastodonInstanceURL,
                token: mastodonToken,
                maxChars: verified.maxCharacters,
                username: verified.username)
            statusIsError = false
            status = "Mastodon verified. Max characters: \(verified.maxCharacters)."
            credentialsChanged(.mastodon)
        } catch {
            statusIsError = true
            status = "Mastodon error: \(error.userMessage)"
        }
    }

    private func verifyBluesky() async {
        verifyingBluesky = true
        defer { verifyingBluesky = false }
        do {
            _ = try await PosterFactory.makeBluesky(handle: blueskyHandle, appPassword: blueskyPassword)
            try store.saveBluesky(handle: blueskyHandle, appPassword: blueskyPassword)
            statusIsError = false
            status = "Bluesky verified for @\(blueskyHandle.trimmingCharacters(in: .whitespacesAndNewlines))."
            credentialsChanged(.bluesky)
        } catch {
            statusIsError = true
            status = "Bluesky error: \(error.userMessage)"
        }
    }

    private func credentialsChanged(_ target: PostTarget) {
        NotificationCenter.default.post(name: .crossPostCredentialsChanged, object: nil,
                                        userInfo: [crossPostTargetsKey: Set([target])])
    }
}
