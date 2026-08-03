import Foundation

class ImageURLProtocolStub: URLProtocol {
    struct Options {
        var delay: TimeInterval = 0
        var declaredContentLength: Int?
        var chunks = 1
        var includesContentLength = true
    }

    private struct Stub {
        let statusCode: Int
        let mimeType: String
        let data: Data
        let delay: TimeInterval
        let declaredContentLength: Int?
        let chunks: Int
        let includesContentLength: Bool
    }

    private static let lock = NSLock()
    private static var stubs: [URL: Stub] = [:]
    private static var requests: [URL: Int] = [:]
    private static var deliveredBytes: [URL: Int] = [:]
    private static var stops: [URL: Int] = [:]

    private let stateLock = NSLock()
    private var stopped = false

    static func requestCount(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests[url, default: 0]
    }

    static func deliveredByteCount(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return deliveredBytes[url, default: 0]
    }

    static func stopCount(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return stops[url, default: 0]
    }

    static func configure(
        url: URL,
        statusCode: Int,
        mimeType: String,
        data: Data,
        options: Options = Options()
    ) {
        lock.lock()
        stubs[url] = Stub(
            statusCode: statusCode,
            mimeType: mimeType,
            data: data,
            delay: options.delay,
            declaredContentLength: options.declaredContentLength,
            chunks: options.chunks,
            includesContentLength: options.includesContentLength
        )
        requests[url] = 0
        deliveredBytes[url] = 0
        stops[url] = 0
        lock.unlock()
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let stub = Self.currentStub(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if stub.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay) { [weak self] in
                self?.deliver(stub)
            }
        } else {
            deliver(stub)
        }
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
        Self.recordStop(for: request.url)
    }

    private static func currentStub(for url: URL) -> Stub? {
        lock.lock()
        defer { lock.unlock() }
        requests[url, default: 0] += 1
        return stubs[url]
    }

    private func deliver(_ stub: Stub) {
        guard !isStopped else { return }
        var headers = ["Content-Type": stub.mimeType]
        if stub.includesContentLength {
            headers["Content-Length"] = String(stub.declaredContentLength ?? stub.data.count)
        }
        guard let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.deliverBody(stub)
        }
    }

    private func deliverBody(_ stub: Stub) {
        guard !isStopped else { return }
        let chunkCount = max(1, stub.chunks)
        let chunkSize = max(1, (stub.data.count + chunkCount - 1) / chunkCount)
        var offset = 0
        while offset < stub.data.count, !isStopped {
            let end = min(stub.data.count, offset + chunkSize)
            let chunk = stub.data[offset ..< end]
            Self.recordDeliveredBytes(chunk.count, for: request.url)
            client?.urlProtocol(self, didLoad: chunk)
            offset = end
        }
        if !isStopped {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private static func recordDeliveredBytes(_ count: Int, for url: URL?) {
        guard let url else { return }
        lock.lock()
        deliveredBytes[url, default: 0] += count
        lock.unlock()
    }

    private static func recordStop(for url: URL?) {
        guard let url else { return }
        lock.lock()
        stops[url, default: 0] += 1
        lock.unlock()
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }
}
