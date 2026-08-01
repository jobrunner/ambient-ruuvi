import XCTest
@testable import ambient_ruuvi

final class DisplayRowsTests: XCTestCase {
    func testRowsContentAndOrder() {
        let d = RuuviData(temperature: 21.4, humidity: 48.5, pressure: 1013.2)
        let rows = d.displayRows
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].label, "Temperatur")
        XCTAssertEqual(rows[0].value, "21.4")
        XCTAssertEqual(rows[0].unit, "°C")
        XCTAssertEqual(rows[1].label, "Luftfeuchtigkeit")
        XCTAssertEqual(rows[1].unit, "%")
        XCTAssertEqual(rows[2].label, "Luftdruck")
        XCTAssertEqual(rows[2].unit, "hPa")
        XCTAssertEqual(rows[3].label, "Taupunkt")
        XCTAssertEqual(rows[3].unit, "°C")
    }

    func testClipboardText() {
        let d = RuuviData(temperature: 21.4, humidity: 48.5, pressure: 1013.2)
        let expected = """
        Temperatur: 21.4 °C
        Luftfeuchtigkeit: 48.5 %
        Luftdruck: 1013.2 hPa
        Taupunkt: \(d.displayRows[3].value) °C
        """
        XCTAssertEqual(d.clipboardText, expected)
    }
}
