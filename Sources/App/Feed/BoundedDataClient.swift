import Foundation

protocol BoundedImageDataLoading: Sendable {
    func data(from url: URL, limit: Int) async throws -> Data
}

final class BoundedDataClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class RequestState {
        let byteLimit: Int
        let continuation: CheckedContinuation<Data, Error>
        var data = Data()
        var acceptedResponse = false

        init(byteLimit: Int, continuation: CheckedContinuation<Data, Error>) {
            self.byteLimit = byteLimit
            self.continuation = continuation
        }
    }

    private final class RequestHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var isCancelled = false

        func install(_ task: URLSessionTask) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isCancelled else { return false }
            self.task = task
            return true
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let task = task
            lock.unlock()
            task?.cancel()
        }
    }

    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var states: [Int: RequestState] = [:]
    private lazy var session = URLSession(
        configuration: configuration,
        delegate: self,
        delegateQueue: nil
    )

    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
        super.init()
    }

    func data(from url: URL, limit: Int) async throws -> Data {
        let handle = RequestHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: url)
                let state = RequestState(byteLimit: limit, continuation: continuation)
                lock.lock()
                states[task.taskIdentifier] = state
                lock.unlock()
                guard handle.install(task) else {
                    finish(task: task, result: .failure(CancellationError()))
                    return
                }
                task.resume()
            }
        } onCancel: {
            handle.cancel()
        }
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let state = state(for: dataTask.taskIdentifier) else {
            completionHandler(.cancel)
            return
        }
        do {
            try validate(response: response, state: state)
            state.acceptedResponse = true
            completionHandler(.allow)
        } catch {
            finish(task: dataTask, result: .failure(error))
            dataTask.cancel()
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard let state = state(for: dataTask.taskIdentifier) else { return }
        guard data.count <= state.byteLimit - state.data.count else {
            finish(
                task: dataTask,
                result: .failure(ImageLoadingError.responseTooLarge(limit: state.byteLimit))
            )
            dataTask.cancel()
            return
        }
        state.data.append(data)
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let state = removeState(for: task.taskIdentifier) else { return }
        if let error {
            state.continuation.resume(throwing: error)
        } else if state.acceptedResponse {
            state.continuation.resume(returning: state.data)
        } else {
            state.continuation.resume(throwing: ImageLoadingError.invalidResponse)
        }
    }

    private func validate(response: URLResponse, state: RequestState) throws {
        guard let response = response as? HTTPURLResponse else {
            throw ImageLoadingError.invalidResponse
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw ImageLoadingError.invalidStatus(response.statusCode)
        }
        guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
            throw ImageLoadingError.invalidMIMEType(response.mimeType)
        }
        let length = response.expectedContentLength
        if length > Int64(state.byteLimit) {
            throw ImageLoadingError.contentLengthExceeded(
                limit: state.byteLimit,
                actual: length
            )
        }
    }

    private func state(for taskIdentifier: Int) -> RequestState? {
        lock.lock()
        defer { lock.unlock() }
        return states[taskIdentifier]
    }

    private func removeState(for taskIdentifier: Int) -> RequestState? {
        lock.lock()
        defer { lock.unlock() }
        return states.removeValue(forKey: taskIdentifier)
    }

    private func finish(task: URLSessionTask, result: Result<Data, Error>) {
        guard let state = removeState(for: task.taskIdentifier) else { return }
        state.continuation.resume(with: result)
    }
}

extension BoundedDataClient: BoundedImageDataLoading {}
