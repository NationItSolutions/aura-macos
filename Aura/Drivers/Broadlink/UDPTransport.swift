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

/// Una interfaz IPv4 activa del Mac (dirección y máscara en orden de host).
struct LocalIPv4Interface: Equatable, Sendable {
    var name: String
    var address: UInt32
    var netmask: UInt32

    var broadcast: UInt32 { address | ~netmask }
    var prefixLength: Int { netmask.nonzeroBitCount }

    /// Hosts de la subred, sin la red, el broadcast ni la propia IP.
    /// Vacío si la subred es más grande que /22 (barrerla sería ruido en la red).
    var sweepHosts: [UInt32] {
        guard prefixLength >= 22, prefixLength <= 30 else { return [] }
        let network = address & netmask
        let last = broadcast
        guard last > network + 1 else { return [] }
        return ((network + 1)..<last).filter { $0 != address }
    }

    static func dotted(_ value: UInt32) -> String {
        "\(value >> 24 & 0xFF).\(value >> 16 & 0xFF).\(value >> 8 & 0xFF).\(value & 0xFF)"
    }

    /// Interfaces IPv4 activas con broadcast (Wi‑Fi, Ethernet), sin loopback ni túneles.
    static func current() -> [LocalIPv4Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [LocalIPv4Interface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  flags & IFF_BROADCAST != 0,
                  let addr = entry.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = entry.ifa_netmask else { continue }
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            guard address != 0, netmask != 0 else { continue }
            let interface = LocalIPv4Interface(name: String(cString: entry.ifa_name), address: address, netmask: netmask)
            if !result.contains(interface) { result.append(interface) }
        }
        return result
    }
}

/// Descubrimiento de Broadlink con sockets BSD.
/// Network.framework no permite enviar broadcast con NWConnection, por eso este caso usa `socket()`.
///
/// Con `address == BroadlinkScanner.everywhere` busca en toda la red local en dos fases:
/// 1. "hello" al broadcast global y al broadcast de cada interfaz (algunos Mac rechazan 255.255.255.255
///    con EHOSTUNREACH y algunos routers no reenvían el broadcast de subred);
/// 2. si nadie respondió, "hello" unicast a cada host de las subredes /22 a /30.
/// Con una IP concreta le pregunta solo a esa IP.
enum BroadlinkScanner {
    static let everywhere = "255.255.255.255"

    /// Destinos de la búsqueda: (broadcasts, hosts para el barrido unicast), como direcciones en texto.
    static func plan(address: String, interfaces: [LocalIPv4Interface]) -> (broadcasts: [String], sweep: [String]) {
        guard address == everywhere else { return ([address], []) }
        var broadcasts = [everywhere]
        for interface in interfaces {
            let value = LocalIPv4Interface.dotted(interface.broadcast)
            if !broadcasts.contains(value) { broadcasts.append(value) }
        }
        var sweep: [String] = []
        var seen = Set<UInt32>()
        for interface in interfaces {
            for host in interface.sweepHosts where seen.insert(host).inserted {
                sweep.append(LocalIPv4Interface.dotted(host))
            }
        }
        return (broadcasts, sweep)
    }

    /// Envía el "hello" según `plan` y junta respuestas durante `timeout`.
    static func scan(
        timeout: Duration = .seconds(5),
        address: String = everywhere,
        date: Date = .now
    ) async throws -> [DiscoveredBroadlink] {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        let packet = BroadlinkProtocol.helloPacket(date: BroadlinkDate(date))
        let targets = plan(address: address, interfaces: address == everywhere ? LocalIPv4Interface.current() : [])
        return try await Task.detached(priority: .userInitiated) {
            try blockingScan(packet: packet, targets: targets, singleHost: address != everywhere, timeout: seconds)
        }.value
    }

    private static func blockingScan(
        packet: [UInt8],
        targets: (broadcasts: [String], sweep: [String]),
        singleHost: Bool,
        timeout: Double
    ) throws -> [DiscoveredBroadlink] {
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

        var found: [DiscoveredBroadlink] = []
        var buffer = [UInt8](repeating: 0, count: 1024)
        let start = Date()
        // El barrido arranca a mitad del tiempo (como mínimo después de 2 rondas de broadcast).
        let sweepStart = start.addingTimeInterval(min(2, timeout / 2))
        var deniedSends = 0
        var totalSends = 0

        /// Envía el hello a `host` (ignora direcciones inválidas).
        func send(to host: String) {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = BroadlinkProtocol.port.bigEndian
            guard inet_pton(AF_INET, host, &target.sin_addr) == 1 else { return }
            totalSends += 1
            let sent = packet.withUnsafeBytes { raw in
                withUnsafePointer(to: &target) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, raw.baseAddress, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            // Un destino que falla (p. ej. EHOSTUNREACH en 255.255.255.255) no corta la búsqueda.
            if sent < 0, errno == EPERM || errno == EACCES { deniedSends += 1 }
        }

        /// Escucha respuestas hasta `deadline`.
        /// Con un `deadline` ya vencido solo vacía lo que esté pendiente, sin bloquear.
        func receive(until deadline: Date) {
            while true {
                var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let waitMs = Int32(max(0, deadline.timeIntervalSinceNow * 1000))
                guard poll(&pollFD, 1, waitMs) > 0 else { return }
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
        }

        let end = start.addingTimeInterval(timeout)
        var swept = false
        while Date() < end {
            if Task.isCancelled { throw CancellationError() }
            for host in targets.broadcasts { send(to: host) }
            if !swept, found.isEmpty, !targets.sweep.isEmpty, Date() >= sweepStart {
                swept = true
                Log.broadlink.info("Sin respuesta al broadcast: barrido unicast de \(targets.sweep.count, privacy: .public) hosts")
                for host in targets.sweep {
                    send(to: host)
                    receive(until: Date())   // vacía respuestas sin bloquear
                }
            }
            if totalSends > 0, deniedSends == totalSends { throw BroadlinkError.localNetworkDenied }
            // Escucha 1 s entre rondas (intervalo de reintento de python-broadlink).
            receive(until: min(Date().addingTimeInterval(1), end))
            // Para una IP directa alcanza con la primera respuesta.
            if singleHost, !found.isEmpty { break }
        }
        return found
    }
}
