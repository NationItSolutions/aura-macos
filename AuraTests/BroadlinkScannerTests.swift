import XCTest
@testable import Aura

/// Plan de búsqueda: broadcasts por interfaz y barrido unicast de la subred.
final class BroadlinkScannerTests: XCTestCase {
    private func ip(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> UInt32 { a << 24 | b << 16 | c << 8 | d }

    private var wifi: LocalIPv4Interface {
        LocalIPv4Interface(name: "en0", address: ip(192, 168, 100, 59), netmask: ip(255, 255, 255, 0))
    }

    func testBroadcastAddressAndPrefix() {
        XCTAssertEqual(LocalIPv4Interface.dotted(wifi.broadcast), "192.168.100.255")
        XCTAssertEqual(wifi.prefixLength, 24)
    }

    func testSweepHostsExcludeNetworkBroadcastAndSelf() {
        let hosts = wifi.sweepHosts.map(LocalIPv4Interface.dotted)
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual(hosts.first, "192.168.100.1")
        XCTAssertEqual(hosts.last, "192.168.100.254")
        XCTAssertFalse(hosts.contains("192.168.100.59"))
        XCTAssertTrue(hosts.contains("192.168.100.64"))
        XCTAssertFalse(hosts.contains("192.168.100.0"))
        XCTAssertFalse(hosts.contains("192.168.100.255"))
    }

    func testLargeSubnetsAreNotSwept() {
        let big = LocalIPv4Interface(name: "en1", address: ip(10, 0, 0, 5), netmask: ip(255, 255, 0, 0))
        XCTAssertTrue(big.sweepHosts.isEmpty)
        let slash22 = LocalIPv4Interface(name: "en2", address: ip(10, 1, 0, 5), netmask: ip(255, 255, 252, 0))
        XCTAssertEqual(slash22.sweepHosts.count, 1021)
    }

    func testPlanForWholeNetwork() {
        let plan = BroadlinkScanner.plan(address: BroadlinkScanner.everywhere, interfaces: [wifi, wifi])
        XCTAssertEqual(plan.broadcasts, ["255.255.255.255", "192.168.100.255"])
        XCTAssertEqual(plan.sweep.count, 253)
    }

    func testPlanForSingleHostSkipsSweep() {
        let plan = BroadlinkScanner.plan(address: "192.168.100.64", interfaces: [wifi])
        XCTAssertEqual(plan.broadcasts, ["192.168.100.64"])
        XCTAssertTrue(plan.sweep.isEmpty)
    }
}
