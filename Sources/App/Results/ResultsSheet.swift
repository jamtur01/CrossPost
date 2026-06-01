import SwiftUI

struct ResultsSheet: View {
    let results: [PostResult]
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results").font(.title2.bold())

            VStack(alignment: .leading, spacing: 14) {
                ForEach(results, id: \.target) { result in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol(result.outcome))
                            .font(.title3)
                            .foregroundStyle(color(result.outcome))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.target.displayName).font(.headline)
                            Text(detail(result.outcome))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done", action: onDismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func symbol(_ o: PostResult.Outcome) -> String {
        switch o {
        case .success: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private func color(_ o: PostResult.Outcome) -> Color {
        switch o {
        case .success: return .green
        case .partial: return .orange
        case .failure: return .red
        }
    }

    private func detail(_ o: PostResult.Outcome) -> String {
        switch o {
        case .success(let posted):
            return posted.compactMap(\.url).joined(separator: "\n").ifEmpty("Posted.")
        case .partial(let posted, let idx, let msg):
            let urls = posted.compactMap(\.url).joined(separator: "\n")
            return "Posted \(posted.count) before post \(idx + 1) failed: \(msg)\n\(urls)"
        case .failure(let msg):
            return msg
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
