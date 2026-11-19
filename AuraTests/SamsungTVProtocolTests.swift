import XCTest
@testable import Aura

/// Mensajes del protocolo Samsung Tizen (sin red).
final class SamsungTVProtocolTests: XCTestCase {
    func testKeyMessageIsExactJSON() {
        XCTAssertEqual(SamsungTVProtocol.keyMessage(.volumeUp),
                       #"{"method":"ms.remote.control","params":{"Cmd":"Click","DataOfCmd":"KEY_VOLUP","Option":"false","TypeOfRemote":"SendRemoteKey"}}"#)
    }

    func testRemoteURLWithAndWithoutToken() throws {
        let plain = try XCTUnwrap(SamsungTVProtocol.remoteURL(host: "192.168.1.40", token: nil))
        XCTAssertEqual(plain.absoluteString, "wss://192.168.1.40:8002/api/v2/channels/samsung.remote.control?name=QXVyYQ==")
        let withToken = try XCTUnwrap(SamsungTVProtocol.remoteURL(host: "192.168.1.40", token: "12345678"))
        XCTAssertTrue(withToken.absoluteString.hasSuffix("&token=12345678"))
    }

    func testApplicationURLValidatesID() {
        XCTAssertEqual(SamsungTVProtocol.applicationURL(host: "10.0.0.2", appID: "111299001912")?.absoluteString,
                       "http://10.0.0.2:8001/api/v2/applications/111299001912")
        XCTAssertNil(SamsungTVProtocol.applicationURL(host: "10.0.0.2", appID: "../evil"))
    }

    func testParseEvents() {
        XCTAssertEqual(SamsungTVProtocol.parseEvent(#"{"event":"ms.channel.connect","data":{"token":"98765"}}"#),
                       .connected(token: "98765"))
        XCTAssertEqual(SamsungTVProtocol.parseEvent(#"{"event":"ms.channel.connect","data":{"token":12345}}"#),
                       .connected(token: "12345"))
        XCTAssertEqual(SamsungTVProtocol.parseEvent(#"{"event":"ms.channel.connect","data":{}}"#), .connected(token: nil))
        XCTAssertEqual(SamsungTVProtocol.parseEvent(#"{"event":"ms.channel.unauthorized"}"#), .unauthorized)
        XCTAssertEqual(SamsungTVProtocol.parseEvent(#"{"event":"ms.channel.timeOut"}"#), .timeout)
        XCTAssertEqual(SamsungTVProtocol.parseEvent(#"{"event":"ed.edenTV.update"}"#), .other("ed.edenTV.update"))
        XCTAssertNil(SamsungTVProtocol.parseEvent("no es json"))
    }

    func testParseInfo() throws {
        let json = #"{"device":{"name":"[TV] Samsung Q60","modelName":"QN55Q60","wifiMac":"AA:BB:CC:DD:EE:FF","PowerState":"standby","TokenAuthSupport":"true"}}"#
        let info = try XCTUnwrap(SamsungTVProtocol.parseInfo(Data(json.utf8)))
        XCTAssertEqual(info.name, "Samsung Q60")
        XCTAssertEqual(info.wifiMac, "aa:bb:cc:dd:ee:ff")
        XCTAssertTrue(info.tokenAuthSupported)
        XCTAssertFalse(info.isOn)
    }

    func testWakeOnLANPacket() throws {
        let mac: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        let packet = try XCTUnwrap(SamsungTVProtocol.wakeOnLANPacket(mac: mac))
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), [UInt8](repeating: 0xFF, count: 6))
        XCTAssertEqual(Array(packet.suffix(6)), mac)
        XCTAssertNil(SamsungTVProtocol.wakeOnLANPacket(mac: [1, 2, 3]))
    }

    func testSSDP() {
        XCTAssertTrue(SamsungTVProtocol.ssdpSearch().contains("ST: urn:samsung.com:device:RemoteControlReceiver:1"))
        let response = "HTTP/1.1 200 OK\r\nST: urn:samsung.com:device:RemoteControlReceiver:1\r\nLOCATION: http://192.168.1.40:7676/smp_15_\r\n\r\n"
        XCTAssertEqual(SamsungTVProtocol.parseSSDPResponse(response), "192.168.1.40")
        XCTAssertNil(SamsungTVProtocol.parseSSDPResponse("HTTP/1.1 200 OK\r\nST: upnp:rootdevice\r\nLOCATION: http://1.2.3.4/\r\n"))
    }
}

/// Automatizaciones: próxima ejecución, días y huso horario.
final class SchedulerTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private func date(_ string: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string) ?? .distantPast
    }

    func testNextFireSameDayAndNextDay() {
        let cal = calendar("America/Asuncion")
        let automation = Automation(name: "A", hour: 18, minute: 30, action: .scene(UUID()))
        // 2026-11-19 es jueves.
        XCTAssertEqual(automation.nextFire(after: date("2026-11-19 10:00", cal), calendar: cal), date("2026-11-19 18:30", cal))
        XCTAssertEqual(automation.nextFire(after: date("2026-11-19 18:30", cal), calendar: cal), date("2026-11-20 18:30", cal))
    }

    func testNextFireRespectsWeekdays() {
        let cal = calendar("America/Asuncion")
        let automation = Automation(name: "A", hour: 7, minute: 0, weekdays: [.monday], action: .scene(UUID()))
        XCTAssertEqual(automation.nextFire(after: date("2026-11-19 10:00", cal), calendar: cal), date("2026-11-23 07:00", cal))
        let weekend = Automation(name: "B", hour: 9, minute: 0, weekdays: [.saturday, .sunday], action: .scene(UUID()))
        XCTAssertEqual(weekend.nextFire(after: date("2026-11-19 10:00", cal), calendar: cal), date("2026-11-21 09:00", cal))
        XCTAssertEqual(weekend.daysSummary, String(localized: "Fines de semana"))
    }

    func testNextFireFollowsTimeZoneChange() {
        let automation = Automation(name: "A", hour: 8, minute: 0, action: .scene(UUID()))
        let instant = date("2026-11-19 12:00", calendar("UTC"))
        let inAsuncion = automation.nextFire(after: instant, calendar: calendar("America/Asuncion"))
        let inSaoPaulo = automation.nextFire(after: instant, calendar: calendar("America/Sao_Paulo"))
        let inTokyo = automation.nextFire(after: instant, calendar: calendar("Asia/Tokyo"))
        // Siempre son las 8:00 locales del huso que corresponda.
        XCTAssertEqual(calendar("America/Asuncion").component(.hour, from: inAsuncion ?? .distantPast), 8)
        XCTAssertEqual(calendar("Asia/Tokyo").component(.hour, from: inTokyo ?? .distantPast), 8)
        XCTAssertNotEqual(inAsuncion, inTokyo)
        XCTAssertNotNil(inSaoPaulo)
    }

    @MainActor
    func testTickRunsDueTimerAndAutomationOnce() async {
        let store = AppStore(file: nil, demo: false)
        let start = Date()
        let clock = MutableClock(start)
        var performed: [String] = []
        let scheduler = Scheduler(store: store, now: { clock.value }) { _, label in
            performed.append(label)
            return true
        }
        store.addTimer(SleepTimer(fireDate: start.addingTimeInterval(5), action: .scene(UUID()), label: "Timer"))
        let components = Calendar.current.dateComponents([.hour, .minute], from: start.addingTimeInterval(60))
        store.upsert(Automation(name: "Auto", hour: components.hour ?? 0, minute: components.minute ?? 0,
                                action: .scene(UUID()), lastRun: start))

        await scheduler.tick()
        XCTAssertEqual(performed, [])
        clock.value = start.addingTimeInterval(90)
        await scheduler.tick()
        XCTAssertEqual(performed.sorted(), ["Auto", "Timer"])
        XCTAssertTrue(store.timers.isEmpty)
        await scheduler.tick()
        XCTAssertEqual(performed.count, 2, "No debe repetir")
    }
}

final class MutableClock: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}

/// Otros modelos de M3/M4/M6.
final class FeatureModelTests: XCTestCase {
    func testACLearningSlots() {
        let slots = LearningSlot.airConditioner(modes: [.cool, .fan], range: 20...22)
        XCTAssertEqual(slots.map(\.codeName), ["on", "off", "swing", "cool_20", "cool_21", "cool_22", "fan"])
        XCTAssertTrue(slots[3].instruction.contains("19"))
    }

    func testSnapshotV1DecodesWithoutNewFields() throws {
        let json = #"{"version":1,"devices":[],"rooms":[],"scenes":[],"bridges":[],"states":[]}"#
        let snapshot = try JSONDecoder().decode(StoreSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.automations.isEmpty)
        XCTAssertTrue(snapshot.timers.isEmpty)
    }

    func testWebhookRequest() throws {
        let action = WebhookAction(name: "Luz", method: .post, url: " http://192.168.1.10:8123/api/webhook/luz ",
                                   headers: ["Authorization": "Bearer x"], body: #"{"on":true}"#)
        let request = try XCTUnwrap(action.request())
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "192.168.1.10")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer x")
        XCTAssertEqual(request.timeoutInterval, 3)
        XCTAssertNil(WebhookAction(name: "Mal", url: "ftp://x").request())
        XCTAssertNil(WebhookAction(name: "GET", method: .get, url: "https://a.b/c", body: "x").request()?.httpBody)
    }

    func testWebhookHeadersParsing() {
        XCTAssertEqual(WebhookActionsSheet.parseHeaders("Authorization: Bearer a:b\nX-Test:1\nbasura"),
                       ["Authorization": "Bearer a:b", "X-Test": "1"])
    }

    func testCommandChoices() {
        let ac = Device(name: "Aire", kind: .airConditioner, transport: .broadlink(bridgeID: nil))
        XCTAssertEqual(CommandChoice.available(for: ac), [.powerOn, .powerOff, .ac])
        let webhook = Device(name: "W", kind: .generic, transport: .webhook(actions: [WebhookAction(name: "On", role: .powerOn)]))
        XCTAssertEqual(CommandChoice.available(for: webhook), [.powerOn, .powerOff])
    }

    func testSleepTimerRemainingText() {
        let now = Date()
        XCTAssertEqual(SleepTimerCard.remaining(until: now.addingTimeInterval(65), now: now), "0:01:05")
    }
}
