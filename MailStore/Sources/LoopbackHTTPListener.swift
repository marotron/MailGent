import Foundation
import Network

public enum LoopbackHTTPListenerError: Error, Equatable, Sendable {
    case invalidPort
    case bindFailed(String)
}

/// Hardened loopback HTTP front for `LoopbackMCPServer`. Binds only the given host (default 127.0.0.1).
public final class LoopbackHTTPListener: @unchecked Sendable {
    public let host: String
    public let port: UInt16
    private let mcp: LoopbackMCPServer

    private let lock = NSLock()
    private var listener: NWListener?
    private var _boundPort: UInt16?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    public var boundPort: UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return _boundPort
    }

    public var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listener != nil
    }

    public init(
        host: LoopbackHost,
        hostAddress: String = "127.0.0.1",
        port: UInt16 = 8788
    ) {
        self.mcp = LoopbackMCPServer(host: host)
        self.host = hostAddress
        self.port = port
    }

    /// Backward-compatible initializer for tests.
    public convenience init(
        gateway: AgentReadAPI,
        ledger: DraftLedger = DraftLedger(),
        indexUpdater: (any IndexUpdating)? = nil,
        sourceController: (any MailSourceControlling)? = nil,
        host: String = "127.0.0.1",
        port: UInt16 = 8788
    ) {
        self.init(
            host: LoopbackHost(
                pairing: gateway.pairing,
                audit: gateway.audit,
                grants: gateway.grants,
                ledger: ledger
            ),
            hostAddress: host,
            port: port
        )
        let box = self.mcp.host
        box.setGateway(gateway, indexUpdater: indexUpdater ?? LocalIndexUpdater(index: gateway.read.index))
        box.setSourceController(sourceController)
        box.setIndexState(
            LoopbackIndexSnapshot(
                phase: .ready,
                indexedSoFar: (try? gateway.read.freshness().indexedCount) ?? 0
            )
        )
    }

    public func start() async throws {
        if isListening { return }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LoopbackHTTPListenerError.invalidPort
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        let created: NWListener
        do {
            created = try NWListener(using: parameters)
        } catch {
            throw LoopbackHTTPListenerError.bindFailed(String(describing: error))
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = StartBox(continuation: continuation)
            created.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let resolved = created.port?.rawValue
                    self?.markReady(listener: created, port: resolved)
                    box.resumeOnce(.success(()))
                case .failed(let error):
                    self?.markStopped()
                    box.resumeOnce(.failure(LoopbackHTTPListenerError.bindFailed(String(describing: error))))
                case .cancelled:
                    self?.markStopped()
                default:
                    break
                }
            }
            created.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            created.start(queue: .global(qos: .userInitiated))
        }
    }

    public func stop() {
        lock.lock()
        let current = listener
        let active = Array(connections.values)
        listener = nil
        _boundPort = nil
        connections.removeAll()
        lock.unlock()
        current?.cancel()
        for connection in active {
            connection.cancel()
        }
    }

    private func markReady(listener: NWListener, port: UInt16?) {
        lock.lock()
        self.listener = listener
        self._boundPort = port
        lock.unlock()
    }

    private func markStopped() {
        lock.lock()
        listener = nil
        _boundPort = nil
        lock.unlock()
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.lock()
        connections[id] = connection
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.forget(connection)
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receiveHTTP(on: connection, buffer: Data())
    }

    private func forget(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.lock()
        connections.removeValue(forKey: id)
        lock.unlock()
    }

    private func receiveHTTP(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                self.forget(connection)
                return
            }
            var next = buffer
            if let data, !data.isEmpty {
                next.append(data)
            }
            if let request = Self.parseHTTP(next) {
                Task {
                    let response = await self.mcp.handle(request)
                    self.send(response, on: connection)
                }
                return
            }
            if isComplete {
                connection.cancel()
                self.forget(connection)
                return
            }
            if next.count > 1_000_000 {
                connection.cancel()
                self.forget(connection)
                return
            }
            self.receiveHTTP(on: connection, buffer: next)
        }
    }

    private func send(_ response: LoopbackMCPResponse, on connection: NWConnection) {
        let payload = Self.encodeHTTP(response)
        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.forget(connection)
        })
    }

    static func parseHTTP(_ data: Data) -> LoopbackMCPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = headers.first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value) } ?? 0
        let bodyStart = headerEnd.upperBound
        let available = data.count - bodyStart
        guard available >= contentLength else { return nil }
        let body = contentLength > 0
            ? data.subdata(in: bodyStart..<(bodyStart + contentLength))
            : Data()
        return LoopbackMCPRequest(method: method, path: path, headers: headers, body: body)
    }

    static func encodeHTTP(_ response: LoopbackMCPResponse) -> Data {
        let bodyData = Data(response.body.utf8)
        var headers = response.headers
        if headers["Content-Type"] == nil, !bodyData.isEmpty {
            headers["Content-Type"] = "application/json"
        }
        headers["Content-Length"] = String(bodyData.count)
        headers["Connection"] = "close"
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        var text = "HTTP/1.1 \(response.status) \(reason)\r\n"
        for key in headers.keys.sorted() {
            text += "\(key): \(headers[key]!)\r\n"
        }
        text += "\r\n"
        var data = Data(text.utf8)
        data.append(bodyData)
        return data
    }
}

private final class StartBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resumeOnce(_ result: Result<Void, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        switch result {
        case .success:
            cont?.resume()
        case .failure(let error):
            cont?.resume(throwing: error)
        }
    }
}
