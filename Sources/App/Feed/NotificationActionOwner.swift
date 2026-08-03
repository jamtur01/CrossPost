import Foundation

/// Owns notification-row work and fences every completion to the row lifecycle
/// that started it.
@MainActor
final class NotificationActionOwner {
    private enum ActionKind: Hashable {
        case postMutation
        case follow
    }

    private struct Completion<Value> {
        let onSuccess: @MainActor (Value) -> Void
        let onFailure: @MainActor (Error) -> Void
        let onFinish: @MainActor () -> Void
    }

    private var tasks: [ActionKind: Task<Void, Never>] = [:]
    private var generation: UInt = 0

    @discardableResult
    func startPostMutation(
        isCurrent: @escaping @MainActor () -> Bool = { true },
        operation: @escaping @MainActor () async throws -> FeedPost,
        onSuccess: @escaping @MainActor (FeedPost) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        start(
            .postMutation,
            isCurrent: isCurrent,
            operation: operation,
            completion: Completion(
                onSuccess: onSuccess,
                onFailure: onFailure,
                onFinish: onFinish
            )
        )
    }

    @discardableResult
    func startFollow(
        isCurrent: @escaping @MainActor () -> Bool = { true },
        operation: @escaping @MainActor () async throws -> AccountRelationship,
        onSuccess: @escaping @MainActor (AccountRelationship) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        start(
            .follow,
            isCurrent: isCurrent,
            operation: operation,
            completion: Completion(
                onSuccess: onSuccess,
                onFailure: onFailure,
                onFinish: onFinish
            )
        )
    }

    func invalidate() {
        generation &+= 1
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func start<Value>(
        _ kind: ActionKind,
        isCurrent: @escaping @MainActor () -> Bool,
        operation: @escaping @MainActor () async throws -> Value,
        completion: Completion<Value>
    ) -> Task<Void, Never> {
        if let task = tasks[kind] {
            return task
        }
        let startedGeneration = generation
        let task = Task { [weak self] in
            guard self?.generation == startedGeneration, isCurrent() else {
                self?.tasks[kind] = nil
                return
            }
            let result: Result<Value, Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            guard let self, self.generation == startedGeneration else { return }
            guard !Task.isCancelled else {
                self.tasks[kind] = nil
                completion.onFinish()
                return
            }
            guard isCurrent() else {
                self.tasks[kind] = nil
                return
            }
            if case let .failure(error) = result, error is CancellationError {
                self.tasks[kind] = nil
                completion.onFinish()
                return
            }
            switch result {
            case let .success(value):
                completion.onSuccess(value)
            case let .failure(error):
                completion.onFailure(error)
            }
            guard self.generation == startedGeneration, isCurrent() else {
                self.tasks[kind] = nil
                return
            }
            self.tasks[kind] = nil
            completion.onFinish()
        }
        tasks[kind] = task
        return task
    }
}
