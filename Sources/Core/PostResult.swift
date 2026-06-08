import Foundation

struct PostResult: Sendable {
    enum Outcome: Sendable {
        case success(posted: [PostedItem])
        case partial(posted: [PostedItem], failedIndex: Int, message: String)
        case failure(message: String)
    }
    let target: PostTarget
    let outcome: Outcome

    init(target: PostTarget, outcome: Outcome) {
        self.target = target
        self.outcome = outcome
    }
}

enum CrossPostOutcome: Sendable {
    case blocked(issues: [ValidationIssue])
    case completed(results: [PostResult])
}
