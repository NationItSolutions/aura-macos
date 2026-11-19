import Darwin
import dnssd
import Foundation
import Network

/// Transporte UDP de pedido/respuesta. Abstracto para poder probar el cliente sin red.
protocol UDPTransport: Sendable {
    /// Envía `packet` y espera la primera respuesta. Reenvía cada `retryInterval` hasta `timeout`.
    func request(_ packet: [UInt8], host: String, port: UInt16, timeout: Duration, retryInterval: Duration) async throws -> [UInt8]
}

/// Implementación con Network.framework (NWConnection), un socket por pedido como python-broadlink.
struct NWUDPTransport: UDPTransport {
    func request(_ packet: [UInt8], host: String, port: UInt16, timeout: Duration, retryInterval: Duration) async throws -> [UInt8] {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw BroadlinkError.invalidResponse }
        let box = ConnectionBox(NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp))
        box.start()
        let payload = Data(packet)

        return try await withThrowingTaskGroup(of: [UInt8].self) { group in
            group.addTask { try await box.receive() }
            group.addTask {
                try await box.waitUntilReady()
                while true {
                    try await box.send(payload)
                    try await Task.sleep(for: retryInterval)
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw box.waitingError ?? BroadlinkError.timeout
            }
            do {
                guard let result = try await group.next() else { throw BroadlinkError.timeout }
                box.cancel()
                group.cancelAll()
                return result
            } catch {
                box.cancel()
                group.cancelAll()
                throw error
            }
        }
    }
}

/// Envuelve una NWConnection y garantiza que cada continuación se resuelva una sola vez.
private final class ConnectionBox: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.nationit.aura.udp")
    private let lock = NSLock()
    private var readyContinuation: CheckedContinuation<Void, any Error>?
    private var isReady = false
    private var finished = false
    private var _waitingError: BroadlinkError?

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    var waitingError: BroadlinkError? {
        lock.lock(); defer { lock.unlock() }
        return _waitingError
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
        connection.start(queue: queue)
    }

    private func handle(_ state: NWConnection.State) {
        lock.lock()
        var toResume: (CheckedContinuation<Void, any Error>, Result<Void, any Error>)?
        switch state {
        case .ready:
            isReady = true
            if let continuation = readyContinuation { toResume = (continuation, .success(())) }
            readyContinuation = nil
        case .waiting(let error):
            // La privacidad de red local de macOS se manifiesta como "PolicyDenied".
            if Self.isPolicyDenied(error) { _waitingError = .localNetworkDenied }
        case .failed(let error):
            finished = true
            let mapped: any Error = Self.isPolicyDenied(error) ? BroadlinkError.localNetworkDenied : BroadlinkError.timeout
            if let continuation = readyContinuation { toResume = (continuation, .failure(mapped)) }
            readyContinuation = nil
        case .cancelled:
            finished = true
            if let continuation = readyContinuation { toResume = (continuation, .failure(CancellationError())) }
            readyContinuation = nil
        default:
            break
        }
        lock.unlock()
        if let pending = toResume { pending.0.resume(with: pending.1) }
    }

    static func isPolicyDenied(_ error: NWError) -> Bool {
        switch error {
        case .dns(let code): return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
        case .posix(let code): return code == .EPERM || code == .EACCES
        default: return false
        }
    }

    func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            if isReady {
                lock.unlock()
                continuation.resume()
            } else if finished {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
            } else {
                readyContinuation = continuation
                lock.unlock()
            }
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: Self.isPolicyDenied(error) ? BroadlinkError.localNetworkDenied : error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receive() async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], any Error>) in
            connection.receiveMessage { data, _, _, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: [UInt8](data))
                } else if let error {
                    continuation.resume(throwing: Self.isPolicyDenied(error) ? BroadlinkError.localNetworkDenied : error)
                } else {
                    continuation.resume(throwing: BroadlinkError.invalidResponse)
                }
            }
        }
    }

    func cancel() {
        connection.cancel()
    }
}

/// Descubrimiento por broadcast UDP con sockets BSD.
/// Network.framework no permite enviar broadcast con NWConnection, por eso este caso usa `socket()`.
enum BroadlinkScanner {
    /// Envía el "hello" a `address` (broadcast por defecto) y junta respuestas durante `timeout`.
    static func scan(
        timeout: Duration = .seconds(3),
        address: String = "255.255.255.255",
        date: Date = .now
    ) async throws -> [DiscoveredBroadlink] {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        let packet = BroadlinkProtocol.helloPacket(date: BroadlinkDate(date))
        return try await Task.detached(priority: .userInitiated) {
            try blockingScan(packet: packet, address: address, timeout: seconds)
        }.value
    }

    private static func blockingScan(packet: [UInt8], address: String, timeout: Double) throws -> [DiscoveredBroadlink] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw BroadlinkError.localNetworkDenied }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = 0
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw BroadlinkError.localNetworkDenied }

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = BroadlinkProtocol.port.bigEndian
        guard inet_pton(AF_INET, address, &target.sin_addr) == 1 else { throw BroadlinkError.notFound }

        var found: [DiscoveredBroadlink] = []
        let start = Date()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while Date().timeIntervalSince(start) < timeout {
            if Task.isCancelled { throw CancellationError() }
            let sent = packet.withUnsafeBytes { raw in
                withUnsafePointer(to: &target) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, raw.baseAddress, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent < 0 {
                if errno == EPERM || errno == EACCES || errno == EHOSTUNREACH { throw BroadlinkError.localNetworkDenied }
                throw BroadlinkError.notFound
            }

            // Escucha respuestas durante 1 s (intervalo de reintento de python-broadlink).
            let roundEnd = min(Date().addingTimeInterval(1), start.addingTimeInterval(timeout))
            while Date() < roundEnd {
                var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let waitMs = Int32(max(1, roundEnd.timeIntervalSinceNow * 1000))
                guard poll(&pollFD, 1, waitMs) > 0 else { break }
                var from = sockaddr_in()
                var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                let bufferCount = buffer.count
                let received = buffer.withUnsafeMutableBytes { raw in
                    withUnsafeMutablePointer(to: &from) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            recvfrom(fd, raw.baseAddress, bufferCount, 0, $0, &fromLength)
                        }
                    }
                }
                guard received > 0 else { continue }
                var hostBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &from.sin_addr, &hostBuffer, socklen_t(INET_ADDRSTRLEN))
                let host = String(decoding: hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if let device = BroadlinkProtocol.parseHello(Array(buffer[0..<received]), host: host),
                   !found.contains(where: { $0.mac == device.mac }) {
                    found.append(device)
                }
            }
            // Para una IP directa alcanza con la primera respuesta.
            if address != "255.255.255.255", !found.isEmpty { break }
        }
        return found
    }
}
