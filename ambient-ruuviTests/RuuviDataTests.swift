import XCTest
@testable import ambient_ruuvi

final class RuuviDataTests: XCTestCase {
    func testDewPointFromTemperatureAndHumidity() {
        // T = 24.3 °C, RH = 53.49 % → Td ≈ 14.2 °C (Magnus a=17.62, b=243.12)
        let d = RuuviData(temperature: 24.3, humidity: 53.49, pressure: 1000.44)
        XCTAssertEqual(d.dewPoint, 14.2, accuracy: 0.1)
    }

    func testFieldsArePreserved() {
        let d = RuuviData(temperature: 20.0, humidity: 50.0, pressure: 1013.2)
        XCTAssertEqual(d.temperature, 20.0, accuracy: 0.001)
        XCTAssertEqual(d.humidity, 50.0, accuracy: 0.001)
        XCTAssertEqual(d.pressure, 1013.2, accuracy: 0.001)
    }
}
