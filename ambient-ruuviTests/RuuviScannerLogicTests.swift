import XCTest
@testable import ambient_ruuvi

final class RuuviScannerLogicTests: XCTestCase {
    private func tag(rssi: Int, ageSeconds: TimeInterval, now: Date) -> RuuviScanner.SeenTag {
        RuuviScanner.SeenTag(
            data: RuuviData(temperature: 20, humidity: 50, pressure: 1013),
            rssi: rssi,
            lastSeen: now.addingTimeInterval(-ageSeconds)
        )
    }

    // The freeze fix: once the only tag stops advertising, its entry ages out,
    // so there is nothing to publish and the UI can be cleared.
    func testStaleTagsAreEvicted() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let tags: [UUID: RuuviScanner.SeenTag] = [
            UUID(): tag(rssi: -50, ageSeconds: 20, now: now)   // older than the 10s expiry
        ]
        let live = RuuviScanner.liveTags(from: tags, now: now, expiry: 10)
        XCTAssertTrue(live.isEmpty)
        XCTAssertNil(RuuviScanner.strongest(in: live))
    }

    func testFreshTagsSurviveAndStrongestWins() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let near = UUID(); let far = UUID()
        let tags: [UUID: RuuviScanner.SeenTag] = [
            near: tag(rssi: -40, ageSeconds: 1, now: now),
            far:  tag(rssi: -80, ageSeconds: 1, now: now),
        ]
        let live = RuuviScanner.liveTags(from: tags, now: now, expiry: 10)
        XCTAssertEqual(live.count, 2)
        XCTAssertEqual(RuuviScanner.strongest(in: live)?.rssi, -40)
    }
}
