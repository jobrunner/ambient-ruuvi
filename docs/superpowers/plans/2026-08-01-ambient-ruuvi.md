# ambient-ruuvi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine maximal einfache SwiftUI-iOS-App, die die Werte des nächsten RuuviTag Pro 4in1 (Temperatur, Luftfeuchtigkeit, Luftdruck, berechneter Taupunkt) live anzeigt, die Signalstärke als Live-Balken darstellt und die 4 Textwerte per Button in die Zwischenablage kopiert.

**Architecture:** Drei kleine Einheiten: `RuuviData` (reines Model mit DF5-Parser, Taupunkt, `displayRows`), `RuuviScanner` (`CBCentralManager`, passives BLE-Scannen der Ruuvi-Advertisements, stärkstes RSSI, `ObservableObject`), `ContentView` (SwiftUI). Kein GATT/Verbindungsaufbau — RuuviTags senden die Daten als BLE-Advertisement. Reine Funktionen (Parser/Taupunkt/Formatierung) werden per XCTest getestet; BLE/UI werden manuell auf echter Hardware verifiziert.

**Tech Stack:** Swift 6, SwiftUI, CoreBluetooth, XCTest, XcodeGen (Projekt­generierung aus `project.yml`), Xcode 26, iOS 16+.

## Global Constraints

- **Bundle-ID:** `io.brunner.ambient-ruuvi`
- **Deployment-Target:** iOS 16.0
- **Datenformat:** Nur Ruuvi Data Format 5 (RAWv2), Hersteller-ID `0x0499`.
- **Tag-Auswahl:** automatisch der Tag mit stärkstem RSSI.
- **Angezeigte/kopierte Textwerte:** genau Temperatur (°C), Luftfeuchtigkeit (%), Luftdruck (hPa), Taupunkt (°C).
- **Signalstärke:** nur als Balken (RSSI-Mapping −100 dBm = leer … −40 dBm = voll), niemals als Textwert, niemals in der Zwischenablage.
- **Copy-Format:** eine Zeile pro Wert, `Bezeichnung: Wert Einheit`.
- **Taupunkt (Magnus):** `a = 17.62`, `b = 243.12`; `γ = (a·T)/(b+T) + ln(RH/100)`, `Td = (b·γ)/(a−γ)`.
- **Zahlenformat:** `String(format:)`, Dezimalpunkt, jeweils 1 Nachkommastelle.
- **Modulname für Tests:** `@testable import ambient_ruuvi` (Bindestrich → Unterstrich).
- **Test-Destination:** `platform=iOS Simulator,name=iPhone 16`.

---

### Task 1: Projekt-Gerüst via XcodeGen

Erzeugt ein baubares SwiftUI-App-Projekt + Unit-Test-Target aus einer `project.yml`. Setup-/Scaffolding-Task; Deliverable = App und Testbundle bauen für den Simulator.

**Files:**
- Create: `project.yml`
- Create: `ambient-ruuvi/ambient_ruuviApp.swift`
- Create: `ambient-ruuvi/ContentView.swift` (Platzhalter)
- Create: `ambient-ruuviTests/PlaceholderTests.swift`
- Create: `ambient-ruuvi/Assets.xcassets/Contents.json`
- Generated (nicht editieren): `ambient-ruuvi.xcodeproj`

**Interfaces:**
- Consumes: nichts.
- Produces: baubares Xcode-Projekt mit App-Target `ambient-ruuvi` (Module `ambient_ruuvi`) und Test-Target `ambient-ruuviTests`; Scheme `ambient-ruuvi` mit Testtarget.

- [ ] **Step 1: `project.yml` schreiben**

```yaml
name: ambient-ruuvi
options:
  bundleIdPrefix: io.brunner
  deploymentTarget:
    iOS: "16.0"
  createIntermediateGroups: true
settings:
  base:
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    GENERATE_INFOPLIST_FILE: YES
    SWIFT_VERSION: "5.0"
targets:
  ambient-ruuvi:
    type: application
    platform: iOS
    sources:
      - path: ambient-ruuvi
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.brunner.ambient-ruuvi
        INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription: "Zum Auslesen der RuuviTag-Sensordaten per Bluetooth."
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
    scheme:
      testTargets:
        - ambient-ruuviTests
  ambient-ruuviTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: ambient-ruuviTests
    dependencies:
      - target: ambient-ruuvi
```

- [ ] **Step 2: App-Entry, Platzhalter-View, Assets, Platzhalter-Test schreiben**

`ambient-ruuvi/ambient_ruuviApp.swift`:
```swift
import SwiftUI

@main
struct AmbientRuuviApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`ambient-ruuvi/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("ambient-ruuvi")
    }
}
```

`ambient-ruuvi/Assets.xcassets/Contents.json`:
```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

`ambient-ruuviTests/PlaceholderTests.swift`:
```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testItBuilds() { XCTAssertTrue(true) }
}
```

- [ ] **Step 3: Projekt generieren**

Run: `xcodegen generate`
Expected: „Created project at .../ambient-ruuvi.xcodeproj"

- [ ] **Step 4: Build + Test laufen lassen**

Run:
```bash
xcodebuild build -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```
Expected: BUILD SUCCEEDED; TEST SUCCEEDED (PlaceholderTests passt).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: scaffold ambient-ruuvi SwiftUI project via XcodeGen"
```

---

### Task 2: `RuuviData`-Model + Taupunkt

Reine Wertestruktur und Taupunktberechnung. Vollständig per XCTest testbar.

**Files:**
- Create: `ambient-ruuvi/RuuviData.swift`
- Test: `ambient-ruuviTests/RuuviDataTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces:
  ```swift
  struct RuuviData: Equatable {
      let temperature: Double   // °C
      let humidity: Double      // %
      let pressure: Double      // hPa
      let dewPoint: Double      // °C
      init(temperature: Double, humidity: Double, pressure: Double)
  }
  ```
  `init` berechnet `dewPoint` aus `temperature`/`humidity` (Magnus).

- [ ] **Step 1: Failing test schreiben**

`ambient-ruuviTests/RuuviDataTests.swift`:
```swift
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
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag prüfen**

Run: `xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ambient-ruuviTests/RuuviDataTests -quiet`
Expected: FAIL („cannot find 'RuuviData'").

- [ ] **Step 3: Minimale Implementierung**

`ambient-ruuvi/RuuviData.swift`:
```swift
import Foundation

struct RuuviData: Equatable {
    let temperature: Double   // °C
    let humidity: Double      // %
    let pressure: Double      // hPa
    let dewPoint: Double      // °C

    init(temperature: Double, humidity: Double, pressure: Double) {
        self.temperature = temperature
        self.humidity = humidity
        self.pressure = pressure
        self.dewPoint = RuuviData.dewPoint(temperature: temperature, humidity: humidity)
    }

    /// Magnus-Formel (a = 17.62, b = 243.12).
    static func dewPoint(temperature t: Double, humidity rh: Double) -> Double {
        let a = 17.62, b = 243.12
        let gamma = (a * t) / (b + t) + log(rh / 100.0)
        return (b * gamma) / (a - gamma)
    }
}
```

- [ ] **Step 4: Test laufen lassen, Erfolg prüfen**

Run: `xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ambient-ruuviTests/RuuviDataTests -quiet`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add RuuviData model with Magnus dew point"
```

---

### Task 3: DF5-Parser

Parst rohe Manufacturer-Advertisement-Daten (inkl. 2-Byte-Hersteller-ID) zu `RuuviData`. Getestet mit dem offiziellen Ruuvi-DF5-Testvektor.

**Files:**
- Modify: `ambient-ruuvi/RuuviData.swift`
- Test: `ambient-ruuviTests/DF5ParserTests.swift`

**Interfaces:**
- Consumes: `RuuviData.init(temperature:humidity:pressure:)` aus Task 2.
- Produces:
  ```swift
  extension RuuviData {
      /// Erwartet die vollständigen Manufacturer-Data-Bytes wie von
      /// CBAdvertisementDataManufacturerDataKey geliefert: 2 Byte Hersteller-ID
      /// (0x99 0x04, little-endian) gefolgt vom DF5-Payload (Byte 0 == 0x05).
      /// Gibt nil bei falscher ID, falschem Format oder ungültigen Messwerten.
      static func parse(manufacturerData: Data) -> RuuviData?
  }
  ```

- [ ] **Step 1: Failing test schreiben**

`ambient-ruuviTests/DF5ParserTests.swift` (offizieller Ruuvi-Testvektor: T=24.3 °C, RH=53.49 %, p=1000.44 hPa):
```swift
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
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag prüfen**

Run: `xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ambient-ruuviTests/DF5ParserTests -quiet`
Expected: FAIL („cannot find member 'parse'").

- [ ] **Step 3: Minimale Implementierung**

An `ambient-ruuvi/RuuviData.swift` anhängen:
```swift
extension RuuviData {
    static func parse(manufacturerData data: Data) -> RuuviData? {
        // 2 Byte ID + mindestens Format..Druck (bis Offset 6 im Payload) = 2 + 7
        guard data.count >= 9 else { return nil }
        let b = [UInt8](data)
        // Hersteller-ID 0x0499 (little-endian): b[0]=0x99, b[1]=0x04
        guard b[0] == 0x99, b[1] == 0x04 else { return nil }
        let p = Array(b[2...])            // DF5-Payload
        guard p[0] == 0x05 else { return nil }

        func i16(_ hi: Int, _ lo: Int) -> Int16 {
            Int16(bitPattern: UInt16(p[hi]) << 8 | UInt16(p[lo]))
        }
        func u16(_ hi: Int, _ lo: Int) -> UInt16 {
            UInt16(p[hi]) << 8 | UInt16(p[lo])
        }

        let rawTemp = i16(1, 2)
        guard rawTemp != Int16(bitPattern: 0x8000) else { return nil } // "nicht verfügbar"
        let temperature = Double(rawTemp) * 0.005

        let rawHum = u16(3, 4)
        guard rawHum != 0xFFFF else { return nil }
        let humidity = Double(rawHum) * 0.0025

        let rawPres = u16(5, 6)
        guard rawPres != 0xFFFF else { return nil }
        let pressure = (Double(rawPres) + 50000.0) / 100.0   // Pa → hPa

        return RuuviData(temperature: temperature, humidity: humidity, pressure: pressure)
    }
}
```

- [ ] **Step 4: Test laufen lassen, Erfolg prüfen**

Run: `xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ambient-ruuviTests/DF5ParserTests -quiet`
Expected: TEST SUCCEEDED (alle 5 Tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add DF5 (RAWv2) manufacturer-data parser"
```

---

### Task 4: `displayRows` + Copy-Text

Eine einzige Quelle für angezeigte Textwerte und Zwischenablage-Text.

**Files:**
- Modify: `ambient-ruuvi/RuuviData.swift`
- Test: `ambient-ruuviTests/DisplayRowsTests.swift`

**Interfaces:**
- Consumes: `RuuviData` aus Task 2.
- Produces:
  ```swift
  extension RuuviData {
      typealias Row = (label: String, value: String, unit: String)
      var displayRows: [Row] { get }   // Temperatur, Luftfeuchtigkeit, Luftdruck, Taupunkt
      var clipboardText: String { get } // "Bezeichnung: Wert Einheit" je Zeile
  }
  ```

- [ ] **Step 1: Failing test schreiben**

`ambient-ruuviTests/DisplayRowsTests.swift`:
```swift
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
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag prüfen**

Run: `xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ambient-ruuviTests/DisplayRowsTests -quiet`
Expected: FAIL („cannot find member 'displayRows'").

- [ ] **Step 3: Minimale Implementierung**

An `ambient-ruuvi/RuuviData.swift` anhängen:
```swift
extension RuuviData {
    typealias Row = (label: String, value: String, unit: String)

    var displayRows: [Row] {
        func f(_ v: Double) -> String { String(format: "%.1f", v) }
        return [
            ("Temperatur",       f(temperature), "°C"),
            ("Luftfeuchtigkeit", f(humidity),    "%"),
            ("Luftdruck",        f(pressure),    "hPa"),
            ("Taupunkt",         f(dewPoint),    "°C"),
        ]
    }

    var clipboardText: String {
        displayRows.map { "\($0.label): \($0.value) \($0.unit)" }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Test laufen lassen, Erfolg prüfen**

Run: `xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ambient-ruuviTests/DisplayRowsTests -quiet`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add displayRows and clipboard text on RuuviData"
```

---

### Task 5: `RuuviScanner` (CoreBluetooth)

Passives BLE-Scannen, DF5-Parsing, stärkstes RSSI, als `ObservableObject`. BLE ist im Simulator/Unit-Test nicht ausführbar → Deliverable ist „baut + integriert korrekt"; echte Werte werden in Task 6 auf Hardware geprüft.

**Files:**
- Create: `ambient-ruuvi/RuuviScanner.swift`

**Interfaces:**
- Consumes: `RuuviData.parse(manufacturerData:)` aus Task 3.
- Produces:
  ```swift
  enum ScannerState: Equatable { case scanning, noTag, bluetoothOff, unauthorized }

  @MainActor
  final class RuuviScanner: NSObject, ObservableObject {
      @Published var data: RuuviData?
      @Published var rssi: Int?
      @Published var state: ScannerState
      func start()
      func stop()
  }
  ```

- [ ] **Step 1: Implementierung schreiben**

`ambient-ruuvi/RuuviScanner.swift`:
```swift
import Foundation
import CoreBluetooth

enum ScannerState: Equatable { case scanning, noTag, bluetoothOff, unauthorized }

@MainActor
final class RuuviScanner: NSObject, ObservableObject {
    @Published var data: RuuviData?
    @Published var rssi: Int?
    @Published var state: ScannerState = .noTag

    private var central: CBCentralManager!
    // Bester (stärkster) RSSI im laufenden Zyklus, damit bei mehreren Tags
    // der nächste gewinnt. Wird pro schwächerem Fund nicht überschrieben.
    private var bestRSSI: Int = Int.min

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else {
            beginScan()
        }
    }

    func stop() {
        central?.stopScan()
    }

    private func beginScan() {
        guard central.state == .poweredOn else { return }
        bestRSSI = Int.min
        state = .scanning
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
}

extension RuuviScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:     beginScan()
            case .poweredOff:    state = .bluetoothOff
            case .unauthorized:  state = .unauthorized
            default:             state = .noTag
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let parsed = RuuviData.parse(manufacturerData: mfg) else { return }
        let r = RSSI.intValue
        Task { @MainActor in
            // Bei mehreren Tags den stärksten bevorzugen; derselbe Tag aktualisiert
            // sich fortlaufend, weil sein RSSI nahe am bisherigen Bestwert liegt.
            if r >= bestRSSI - 5 {
                bestRSSI = max(bestRSSI, r)
                data = parsed
                rssi = r
                state = .scanning
            }
        }
    }
}
```

- [ ] **Step 2: Build prüfen**

Run: `xcodebuild build -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Bestehende Tests laufen lassen (Regression)**

Run: `xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: TEST SUCCEEDED (Tasks 2–4 weiterhin grün).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add RuuviScanner passive BLE scanner (strongest RSSI)"
```

---

### Task 6: `ContentView` (UI: Werteliste, RSSI-Balken, Copy-Button)

Finale UI. Deliverable: baut; auf echtem iPhone manuell verifiziert.

**Files:**
- Modify: `ambient-ruuvi/ContentView.swift`

**Interfaces:**
- Consumes: `RuuviScanner` (Task 5), `RuuviData.displayRows`/`clipboardText` (Task 4), `ScannerState` (Task 5).
- Produces: finale App-UI.

- [ ] **Step 1: Implementierung schreiben**

`ambient-ruuvi/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = RuuviScanner()

    var body: some View {
        VStack(spacing: 24) {
            Text("RuuviTag")
                .font(.largeTitle.bold())

            SignalBar(rssi: scanner.rssi)

            if let data = scanner.data {
                VStack(spacing: 12) {
                    ForEach(data.displayRows, id: \.label) { row in
                        HStack {
                            Text(row.label)
                            Spacer()
                            Text("\(row.value) \(row.unit)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    UIPasteboard.general.string = data.clipboardText
                } label: {
                    Label("In Zwischenablage kopieren", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(hint)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
    }

    private var hint: String {
        switch scanner.state {
        case .scanning:     return "Suche RuuviTag…"
        case .noTag:        return "Suche RuuviTag…"
        case .bluetoothOff: return "Bitte Bluetooth einschalten."
        case .unauthorized: return "Bitte Bluetooth-Berechtigung erlauben."
        }
    }
}

/// RSSI-Live-Balken: −100 dBm = leer, −40 dBm = voll.
struct SignalBar: View {
    let rssi: Int?

    private var level: Double {
        guard let rssi else { return 0 }
        return min(1, max(0, Double(rssi + 100) / 60.0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text(rssi.map { "\($0) dBm" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.green)
                        .frame(width: geo.size.width * level)
                }
            }
            .frame(height: 10)
            .animation(.easeOut(duration: 0.2), value: level)
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 2: Build prüfen**

Run: `xcodebuild build -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Volle Testsuite (Regression)**

Run: `xcodebuild test -project ambient-ruuvi.xcodeproj -scheme ambient-ruuvi -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: TEST SUCCEEDED.

- [ ] **Step 4: Manuelle Verifikation auf echtem iPhone** (Hardware nötig — Simulator hat kein BLE)

  1. App auf iPhone in Reichweite eines RuuviTag Pro 4in1 starten.
  2. Bluetooth-Berechtigungsdialog erscheint → erlauben.
  3. Innerhalb weniger Sekunden erscheinen 4 Werte (Temperatur, Luftfeuchtigkeit, Luftdruck, Taupunkt); der Signalbalken bewegt sich beim Annähern/Entfernen live.
  4. „In Zwischenablage kopieren" tippen → in Notizen/Nachrichten einfügen → 4 Zeilen `Bezeichnung: Wert Einheit`, **ohne** Signalstärke.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ContentView with value list, live RSSI bar, copy button"
```

---

## Self-Review

**Spec coverage:**
- Nur DF5 / Hersteller-ID 0x0499 → Task 3. ✓
- Stärkstes RSSI → Task 5 (`bestRSSI`). ✓
- 4 Textwerte inkl. Taupunkt → Tasks 2–4, angezeigt in Task 6. ✓
- Signalstärke nur als Live-Balken, nicht in Copy → Task 6 (`SignalBar`), Copy nutzt `clipboardText` (nur 4 Rows). ✓
- Copy-Format `Bezeichnung: Wert Einheit` → Task 4 (getestet). ✓
- Nicht angezeigte Felder (Beschleunigung/Batterie/TX/…) → im Parser schlicht übersprungen (nicht geparst/gespeichert), YAGNI. ✓
- Fehler/Randfälle (kein Tag, BT aus, Berechtigung) → Task 5 `ScannerState` + Task 6 `hint`. ✓
- `NSBluetoothAlwaysUsageDescription` → Task 1 (`INFOPLIST_KEY_...`). ✓
- Bundle-ID / iOS 16 → Task 1. ✓

**Hinweis zur Spec-Abweichung:** Statt einer separaten `Info.plist`-Datei wird die Bluetooth-Beschreibung über `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` (generierte Info.plist) gesetzt — gleiches Ergebnis, weniger Dateien, passt zu „maximal einfach".

**Placeholder scan:** keine TBD/TODO/„handle edge cases"; alle Code-Schritte vollständig. ✓

**Type consistency:** `RuuviData.init(temperature:humidity:pressure:)`, `parse(manufacturerData:)`, `displayRows`, `clipboardText`, `RuuviScanner.data/rssi/state`, `ScannerState` durchgängig identisch in Tasks 2–6. ✓
