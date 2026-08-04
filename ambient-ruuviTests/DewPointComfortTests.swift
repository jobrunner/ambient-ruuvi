import XCTest
@testable import ambient_ruuvi

final class DewPointComfortTests: XCTestCase {
    func testClassificationBoundaries() {
        // Grenzfälle jeder Schwelle: knapp darunter bleibt in der Stufe,
        // der Schwellenwert selbst wechselt in die nächste.
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 9.9),  .dry)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 10.0), .comfortable)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 12.9), .comfortable)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 13.0), .moderate)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 15.9), .moderate)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 16.0), .muggy)      // DWD-Schwülegrenze
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 17.9), .muggy)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 18.0), .veryMuggy)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 20.9), .veryMuggy)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 21.0), .oppressive)
    }

    func testExtremes() {
        XCTAssertEqual(DewPointComfort.classify(dewPoint: -5.0), .dry)
        XCTAssertEqual(DewPointComfort.classify(dewPoint: 30.0), .oppressive)
    }

    func testNonFiniteDewPointHasNoClassification() {
        XCTAssertNil(DewPointComfort.classify(dewPoint: .nan))
        XCTAssertNil(DewPointComfort.classify(dewPoint: -.infinity))

        // Feuchte 0 % treibt die Magnus-Formel auf NaN → kein Label, keine note.
        let degenerate = RuuviData(temperature: 20.0, humidity: 0.0, pressure: 1013.2)
        XCTAssertNil(degenerate.dewPointComfort)
        let dewRow = degenerate.displayRows.first { $0.label == "Taupunkt" }
        XCTAssertNil(dewRow?.note)
    }

    func testOnlyDewPointRowCarriesNote() {
        let rows = RuuviData(temperature: 21.4, humidity: 48.5, pressure: 1013.2).displayRows
        for row in rows where row.label != "Taupunkt" {
            XCTAssertNil(row.note, "\(row.label) darf keine Einordnung tragen")
        }
        let dewRow = rows.first { $0.label == "Taupunkt" }
        XCTAssertEqual(dewRow?.note, "behaglich") // Taupunkt ≈ 10.1 °C → behaglich
    }
}
