import Darwin
import Foundation

/// UDP con sockets BSD para Wake-on-LAN (broadcast) y SSDP (multicast),
/// que NWConnection no permite enviar.
enum LocalUDP {
    /// Manda `packet` a cada destino. Devuelve cuántos envíos salieron bien.
    @discardableResult
    static func send(_ packet: [UInt8], to hosts: [String], port: UInt16) -> Int {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return 0 }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var sent = 0
        for host in hosts {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = port.bigEndian
            guard inet_pton(AF_INET, host, &target.sin_addr) == 1 else { continue }
            let result = packet.withUnsafeBytes { raw in
                withUnsafePointer(to: &target) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, raw.baseAddress, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if result >= 0 { sent += 1 }
        }
        return sent
    }

    /// Broadcast global + broadcast de cada interfaz (algunos Mac rechazan 255.255.255.255).
    static func broadcastAddresses() -> [String] {
        BroadlinkScanner.plan(address: BroadlinkScanner.everywhere, interfaces: LocalIPv4Interface.current()).broadcasts
    }

    /// Envía el paquete mágico 3 veces a los puertos 9 y 7.
    static func wake(mac: [UInt8]) async -> Bool {
        guard let packet = SamsungTVProtocol.wakeOnLANPacket(mac: mac) else { return false }
        let targets = broadcastAddresses()
        var anySent = false
        for _ in 0..<3 {
            if send(packet, to: targets, port: 9) > 0 { anySent = true }
            send(packet, to: targets, port: 7)
            try? await Task.sleep(for: .milliseconds(150))
        }
        return anySent
    }

    /// Busca TVs Samsung por SSDP y devuelve sus IPs.
    static func discoverSamsungTVs(timeout: Duration = .seconds(3)) async -> [String] {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        return await Task.detached(priority: .userInitiated) { blockingSSDP(timeout: seconds) }.value
    }

    private static func blockingSSDP(timeout: Double) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { return [] }

        let message = Array(SamsungTVProtocol.ssdpSearch().utf8)
        var hosts: [String] = []
        var buffer = [UInt8](repeating: 0, count: 2048)
        let end = Date().addingTimeInterval(timeout)
        var lastSend = Date.distantPast
        while Date() < end {
            if Date().timeIntervalSince(lastSend) >= 1 {
                send(message, to: ["239.255.255.250"], port: 1900)
                // Algunas redes filtran multicast: también por broadcast.
                send(message, to: broadcastAddresses(), port: 1900)
                lastSend = Date()
            }
            var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pollFD, 1, 250) > 0 else { continue }
            let count = buffer.count
            let received = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, count, 0) }
            guard received > 0 else { continue }
            let text = String(decoding: buffer[0..<received], as: UTF8.self)
            if let host = SamsungTVProtocol.parseSSDPResponse(text), !hosts.contains(host) {
                hosts.append(host)
            }
        }
        return hosts
    }
}
