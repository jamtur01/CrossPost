import Foundation
import Observation

/// One editor's @-mention autocomplete: tracks the query at the caret, runs a
/// debounced search, and holds the suggestions and keyboard selection.
@MainActor
@Observable
final class MentionCompletion {
    typealias Search = @MainActor (String) async -> MentionDirectory.Results

    private(set) var query: MentionQuery?
    private(set) var people: [MentionPerson] = []
    private(set) var failureMessage: String?
    private(set) var selectedIndex = 0
    /// Set by the editor: replaces the query range with the chosen mention.
    @ObservationIgnored var insert: ((MentionPerson, NSRange) -> Void)?
    @ObservationIgnored private let search: Search
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var task: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(250), search: @escaping Search) {
        self.debounce = debounce
        self.search = search
    }

    var isActive: Bool {
        query != nil && (!people.isEmpty || failureMessage != nil)
    }

    var selected: MentionPerson? {
        people.indices.contains(selectedIndex) ? people[selectedIndex] : nil
    }

    func update(text: String, caret: Int) {
        let next = MentionQuery.detect(in: text, caret: caret)
        guard let next else {
            dismiss()
            return
        }
        let queryChanged = next.text != query?.text
        query = next
        guard queryChanged else { return }
        task?.cancel()
        task = Task { [weak self, search, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let results = await search(next.text)
            guard !Task.isCancelled else { return }
            self?.show(results)
        }
    }

    func dismiss() {
        task?.cancel()
        task = nil
        query = nil
        people = []
        failureMessage = nil
        selectedIndex = 0
    }

    func moveSelection(by delta: Int) {
        guard !people.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + people.count) % people.count
    }

    /// Inserts `person` (default: the selected row) over the query and closes.
    func choose(_ person: MentionPerson? = nil) {
        guard let person = person ?? selected, let range = query?.range else { return }
        dismiss()
        insert?(person, range)
    }

    private func show(_ results: MentionDirectory.Results) {
        people = results.people
        selectedIndex = 0
        if results.people.isEmpty, !results.failed.isEmpty {
            let names = results.failed.map(\.displayName).joined(separator: " or ")
            failureMessage = "Couldn't search \(names)."
        } else {
            failureMessage = nil
        }
    }
}
