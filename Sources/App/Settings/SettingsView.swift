import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AccountStore
    @State private var mastodonInstanceURL: String = ""
    @State private var mastodonToken: String = ""
    @State private var blueskyHandle: String = ""
    @State private var blueskyPassword: String = ""
    @State private var status: [PostTarget: String] = [:]
    @AppStorage("readingTextSize", store: AccountStore.defaults) private var readingTextSize = ReadingTextSize.standard
    @State private var failedTargets: Set<PostTarget> = []
    @State private var verifyingMastodon = false
    @State private var verifyingBluesky = false

    var body: some View {
        Form {
            mastodonSection
            blueskySection
            Section("Reading") {
                Picker("Text size", selection: $readingTextSize) {
                    ForEach(ReadingTextSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                Text("Applies to posts, quotations, profile bios, and messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: Self.appVersion)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 12)
        .frame(width: 520, height: 660)
        .onAppear {
            mastodonInstanceURL = store.mastodonInstanceURL
            mastodonToken = store.mastodonToken
            blueskyHandle = store.blueskyHandle
            blueskyPassword = store.blueskyAppPassword
        }
    }

    private var mastodonSection: some View {
        Section("Mastodon") {
            TextField("Instance URL", text: $mastodonInstanceURL)
                .textContentType(.URL)
            SecureField("Access token", text: $mastodonToken)
            Text("Create an application in your instance's Development settings. "
                + "Enable read and write, then copy its access token here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let base = AccountStore.normalizedMastodonBaseURL(from: mastodonInstanceURL) {
                Link("Open token settings", destination: base.appending(path: "settings/applications"))
            }
            verifyButton(title: "Verify & Save Mastodon", ready: mastodonReady,
                         verifying: verifyingMastodon) {
                await verifyMastodon()
            }
            accountStatus(.mastodon, configured: store.hasMastodon, handle: store.mastodonUsername)
        }
    }

    private var blueskySection: some View {
        Section("Bluesky") {
            TextField("Handle (e.g. you.bsky.social)", text: $blueskyHandle)
            SecureField("App password", text: $blueskyPassword)
            Text("Use an app password. Enable Direct Messages access if you want to read and send messages here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let url = URL(string: "https://bsky.app/settings/app-passwords") {
                Link("Create an app password", destination: url)
            }
            verifyButton(title: "Verify & Save Bluesky", ready: blueskyReady,
                         verifying: verifyingBluesky) {
                await verifyBluesky()
            }
            accountStatus(.bluesky, configured: store.hasBluesky, handle: store.blueskyHandle)
        }
    }

    @ViewBuilder
    private func accountStatus(_ target: PostTarget, configured: Bool, handle: String) -> some View {
        Label(
            configured ? (handle.isEmpty ? "Account saved" : "Saved account: @\(handle)") : "Not connected",
            systemImage: configured ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        if let message = status[target] {
            Label(message, systemImage: failedTargets.contains(target)
                ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(failedTargets.contains(target) ? .orange : .primary)
                .textSelection(.enabled)
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
                if verifying {
                    ProgressView().controlSize(.small)
                }
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
        status[.mastodon] = nil
        defer { verifyingMastodon = false }
        // Snapshot the fields the user verified: they stay editable during the await,
        // so saving the live fields could persist a pair that was never verified.
        let instanceURL = mastodonInstanceURL
        let token = mastodonToken
        do {
            let verified = try await PosterFactory.makeMastodon(instanceURL: instanceURL, token: token)
            try store.saveMastodon(
                instanceURL: instanceURL,
                token: token,
                maxChars: verified.maxCharacters,
                username: verified.username
            )
            failedTargets.remove(.mastodon)
            status[.mastodon] = "Verified and saved. Character limit: \(verified.maxCharacters)."
            credentialsChanged(.mastodon)
        } catch {
            failedTargets.insert(.mastodon)
            status[.mastodon] = "Verification failed: \(error.userMessage)"
        }
    }

    private func verifyBluesky() async {
        verifyingBluesky = true
        status[.bluesky] = nil
        defer { verifyingBluesky = false }
        // Snapshot the verified credentials (the fields stay editable during the await).
        let handle = blueskyHandle
        let password = blueskyPassword
        do {
            _ = try await PosterFactory.makeBluesky(handle: handle, appPassword: password)
            try store.saveBluesky(handle: handle, appPassword: password)
            failedTargets.remove(.bluesky)
            status[.bluesky] = "Verified and saved."
            credentialsChanged(.bluesky)
        } catch {
            failedTargets.insert(.bluesky)
            status[.bluesky] = "Verification failed: \(error.userMessage)"
        }
    }

    private func credentialsChanged(_ target: PostTarget) {
        NotificationCenter.default.post(name: .crossPostCredentialsChanged, object: nil,
                                        userInfo: [crossPostTargetsKey: Set([target])])
    }
}
