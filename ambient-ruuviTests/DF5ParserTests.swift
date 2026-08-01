import XCTest
@testable import ambient_ruuvi

final class DF5ParserTests: XCTestCase {
    // 0x9904 (Hersteller-ID, LE) + DF5-Payload aus der Ruuvi-Spezifikation.
    private let validBytes: [UInt8] = [
        0x99, 0x04,
        0x05, 0x12, 0xFC, 0x53, 0x94, 0xC3, 0x7C, 0x00, 0x04,
        0xFF, 0xFC, 0x04, 0x0C, 0xAC, 0x36, 0x42, 0x00, 0xCD,
        0xCB, 0xB8, 0x33, 0x4C, 0x88, 0x4F
    ]

    func testParsesOfficialVector() {
        let d = RuuviData.parse(manufacturerData: Data(validBytes))
        XCTAssertNotNil(d)
        XCTAssertEqual(d!.temperature, 24.3, accuracy: 0.01)
        XCTAssertEqual(d!.humidity, 53.49, accuracy: 0.01)
        XCTAssertEqual(d!.pressure, 1000.44, accuracy: 0.01)
        XCTAssertEqual(d!.dewPoint, 14.2, accuracy: 0.1)
    }

    func testRejectsWrongManufacturerId() {
        var b = validBytes; b[0] = 0x4C; b[1] = 0x00 // Apple
        XCTAssertNil(RuuviData.parse(manufacturerData: Data(b)))
    }

    func testRejectsWrongFormatByte() {
        var b = validBytes; b[2] = 0x03 // DF3, nicht unterstützt
        XCTAssertNil(RuuviData.parse(manufacturerData: Data(b)))
    }

    func testRejectsTooShort() {
        XCTAssertNil(RuuviData.parse(manufacturerData: Data([0x99, 0x04, 0x05])))
    }

    func testRejectsInvalidTemperature() {
        // 0x8000 = "nicht verfügbar" laut DF5-Spezifikation.
        var b = validBytes; b[3] = 0x80; b[4] = 0x00
        XCTAssertNil(RuuviData.parse(manufacturerData: Data(b)))
    }
}
