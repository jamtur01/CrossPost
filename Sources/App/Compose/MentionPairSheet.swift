import SwiftUI

/// Chooses a mention's account on one network by hand. The choice fills the
/// mention and is saved as a pair, so later searches show the person as one row.
struct MentionPairSheet: View {
    let request: MentionPairingRequest
    let model: ComposeModel

    @State private var query: String
    @State private var people: [MentionPerson] = []
    @State private var failed = false
    @State private var searching = false

    init(request: MentionPairingRequest, model: ComposeModel) {
        self.request = request
        self.model = model
        _query = State(initialValue: request.span.person.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHeader(icon: "at", label: "Choose \(request.target.displayName) Account",
                        accent: request.target.accent)
            Text("For \(subject). CrossPost remembers this pairing for later mentions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Search \(request.target.displayName)", text: $query)
                .textFieldStyle(.roundedBorder)
            results
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 280, alignment: .topLeading)
            HStack {
                Spacer()
                Button("Cancel") { model.pairing = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .sheetContainer()
        .task(id: query) { await search() }
    }

    private var results: some View {
        AccountSearchResults(network: request.target, failed: failed, searching: searching,
                             isEmpty: people.isEmpty, query: query) {
            ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                Button { model.completePairing(with: person) } label: {
                    MentionPersonRow(person: person)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subject: String {
        let person = request.span.person
        return person.displayName.isEmpty ? person.visibleText : "\(person.displayName) (\(person.visibleText))"
    }

    private func search() async {
        let query = AccountQuery.normalized(query)
        guard query.count >= AccountQuery.minLength else {
            people = []
            failed = false
            return
        }
        do {
            try await Task.sleep(for: AccountQuery.debounce)
        } catch {
            return // A newer query replaced this one.
        }
        searching = true
        defer { searching = false }
        let found = await model.mentionDirectory.search(query, on: [request.target])
        guard !Task.isCancelled else { return }
        people = found.people
        failed = !found.failed.isEmpty
    }
}
