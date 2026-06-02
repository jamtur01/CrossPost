import Foundation

public struct PostResult: Sendable {
    public enum Outcome: Sendable {
        case success(posted: [PostedItem])
        case partial(posted: [PostedItem], failedIndex: Int, message: String)
        case failure(message: String)
    }
    public let target: PostTarget
    public let outcome: Outcome

    public init(target: PostTarget, outcome: Outcome) {
        self.target = target
        self.outcome = outcome
    }
}

public enum CrossPostOutcome: Sendable {
    case blocked(issues: [ValidationIssue])
    case completed(results: [PostResult])
}
