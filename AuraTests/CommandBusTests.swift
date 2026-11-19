import XCTest
@testable import Aura

/// Driver de prueba programable.
actor ScriptedDriver: DeviceDriver {
    nonisolated let capabilities: Set<Capability> = [.power]
    var failuresBeforeSuccess: Int
    var error: any Error
    var delay: Duration
    private(set) var sendCount = 0
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var log: [String] = []

    init(failuresBeforeSuccess: Int = 0, error: any Error = DriverError.unreachable, delay: Duration = .zero) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.error = error
        self.delay = delay
    }

    var isReachable: Bool { true }
    func connect() async throws { connectCount += 1 }
    func disconnect() async { disconnectCount += 1 }

    func send(_ command: Command) async throws {
        sendCount += 1
        log.append("start \(sendCount)")
        if delay > .zero { try await Task.sleep(for: delay) }
        log.append("end \(sendCount)")
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw error
        }
    }
}

@MainActor
final class CommandBusTests: XCTestCase {
    private let device = Device(name: "Test", kind: .light, transport: .broadlink(bridgeID: nil))

    func testSuccessPublishesFeedback() async {
        let driver = ScriptedDriver()
        let bus = CommandBus { _ in driver }
        let result = await bus.send(.power(true), to: device)
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(bus.lastFeedback?.isError, false)
        XCTAssertFalse(bus.isBusy(device.id))
    }

    func testRetriesOnceWithReconnect() async {
        let driver = ScriptedDriver(failuresBeforeSuccess: 1)
        let bus = CommandBus { _ in driver }
        let result = await bus.send(.power(true), to: device)
        XCTAssertNoThrow(try result.get())
        let sends = await driver.sendCount
        let connects = await driver.connectCount
        let disconnects = await driver.disconnectCount
        XCTAssertEqual(sends, 2)
        XCTAssertEqual(connects, 1)
        XCTAssertEqual(disconnects, 1)
    }

    func testFailsAfterSecondFailure() async {
        let driver = ScriptedDriver(failuresBeforeSuccess: 5)
        let bus = CommandBus { _ in driver }
        let result = await bus.send(.power(true), to: device)
        XCTAssertThrowsError(try result.get())
        let sends = await driver.sendCount
        XCTAssertEqual(sends, 2)
        XCTAssertEqual(bus.lastFeedback?.isError, true)
    }

    func testConfigurationErrorsAreNotRetried() async {
        let driver = ScriptedDriver(failuresBeforeSuccess: 1, error: DriverError.missingCode("cool_23"))
        let bus = CommandBus { _ in driver }
        let result = await bus.send(.power(true), to: device)
        guard case .failure(let failure) = result else { return XCTFail("Debía fallar") }
        XCTAssertTrue(failure.message.contains("cool_23"))
        let sends = await driver.sendCount
        XCTAssertEqual(sends, 1)
    }

    func testTimeout() async {
        let driver = ScriptedDriver(delay: .seconds(5))
        let bus = CommandBus { _ in driver }
        bus.timeout = .milliseconds(100)
        let start = ContinuousClock.now
        let result = await bus.send(.power(true), to: device)
        let elapsed = ContinuousClock.now - start
        guard case .failure(let failure) = result else { return XCTFail("Debía fallar por timeout") }
        XCTAssertEqual(failure.message, TimeoutError().userMessage)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    func testCommandsAreSerializedPerDevice() async {
        let driver = ScriptedDriver(delay: .milliseconds(80))
        let bus = CommandBus { _ in driver }
        let device = self.device
        async let first = bus.send(.power(true), to: device)
        async let second = bus.send(.color("blue"), to: device)
        async let third = bus.send(.power(false), to: device)
        _ = await (first, second, third)
        let log = await driver.log
        XCTAssertEqual(log, ["start 1", "end 1", "start 2", "end 2", "start 3", "end 3"])
        XCTAssertFalse(bus.isBusy(device.id))
    }

    func testDifferentDevicesRunInParallel() async {
        let slow = ScriptedDriver(delay: .milliseconds(300))
        let fast = ScriptedDriver()
        let other = Device(name: "Otro", kind: .light, transport: .broadlink(bridgeID: nil))
        let slowID = device.id
        let bus = CommandBus { $0.id == slowID ? slow : fast }
        let device = self.device
        let start = ContinuousClock.now
        async let a = bus.send(.power(true), to: device)
        async let b = bus.send(.power(true), to: other)
        _ = await b
        let fastElapsed = ContinuousClock.now - start
        _ = await a
        XCTAssertLessThan(fastElapsed, .milliseconds(250))
    }
}
