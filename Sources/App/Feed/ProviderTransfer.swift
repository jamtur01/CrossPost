import Foundation

final class ProviderTransfer<Value: Sendable>: @unchecked Sendable {
    typealias Completion = @Sendable (Value) -> Void

    private enum State: Equatable {
        case pending
        case completed
        case cancelled
    }

    private let lock = NSLock()
    private var state = State.pending
    private var continuation: CheckedContinuation<Value, Error>?
    private var progress: Progress?

    func start(
        continuation: CheckedContinuation<Value, Error>,
        operation: (@escaping Completion) -> Progress
    ) {
        let shouldStart = lock.withLock {
            guard state == .pending else { return false }
            self.continuation = continuation
            return true
        }
        guard shouldStart else {
            continuation.resume(throwing: CancellationError())
            return
        }

        let progress = operation { [self] value in
            complete(with: value)
        }
        install(progress)
    }

    func cancel() {
        let pending: (CheckedContinuation<Value, Error>?, Progress?) = lock.withLock {
            guard state == .pending else { return (nil, nil) }
            state = .cancelled
            defer {
                continuation = nil
                progress = nil
            }
            return (continuation, progress)
        }
        pending.1?.cancel()
        pending.0?.resume(throwing: CancellationError())
    }

    private func complete(with value: Value) {
        let continuation: CheckedContinuation<Value, Error>? = lock.withLock {
            guard state == .pending else { return nil }
            state = .completed
            defer {
                self.continuation = nil
                progress = nil
            }
            return self.continuation
        }
        continuation?.resume(returning: value)
    }

    private func install(_ progress: Progress) {
        let shouldCancel = lock.withLock {
            guard state == .pending else {
                return state == .cancelled
            }
            self.progress = progress
            return false
        }
        if shouldCancel {
            progress.cancel()
        }
    }
}
