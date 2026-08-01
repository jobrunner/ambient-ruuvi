# ambient-ruuvi — Design

## Zweck

Eine maximal einfache SwiftUI-iOS-App, die die Messwerte des nächstgelegenen
**RuuviTag Pro 4in1** live anzeigt (inkl. berechnetem Taupunkt) und per Button
die angezeigten Textwerte in die iOS-Zwischenablage kopiert.

Angelehnt an die bestehende Objective-C-App `../ambient` (TI SensorTag), aber in
**Swift/SwiftUI** und für einen RuuviTag. Wichtiger technischer Unterschied: Ein
RuuviTag baut **keine** GATT-Verbindung auf, sondern **sendet die Werte
permanent als BLE-Advertisement (Beacon)**. Die App scannt daher nur passiv und
parst die Hersteller-Daten — deutlich einfacher als der SensorTag-Flow.

## Scope-Entscheidungen

- **Datenformat:** Nur **DF5 / RAWv2** (Ruuvi Data Format 5). Ein Parser.
- **Tag-Auswahl:** Automatisch der RuuviTag mit dem **stärksten RSSI** (am
  nächsten). Keine Auswahl-UI.
- **UI:** SwiftUI, **ein einziger Screen**.
- **Bundle-ID:** `io.brunner.ambient-ruuvi`
- **Deployment-Target:** iOS 16+
- **Hardware:** Nur echtes iPhone (Simulator hat kein BLE).

## Angezeigte Werte

**Textwerte (Label · Wert · Einheit):**

| Bezeichnung       | Einheit | Quelle               |
|-------------------|---------|----------------------|
| Temperatur        | °C      | DF5                  |
| Luftfeuchtigkeit  | %       | DF5                  |
| Luftdruck         | hPa     | DF5                  |
| Taupunkt          | °C      | berechnet (Magnus)   |

**Signalstärke (RSSI):** als **Live-Balken** (kein Textwert), aktualisiert sich
in Echtzeit mit jedem empfangenen Advertisement.

**Geparst, aber NICHT angezeigt** (im DF5-Payload enthalten, hier ungenutzt):
Beschleunigung X/Y/Z, Batteriespannung, TX-Power, Bewegungszähler,
Mess-Sequenznummer, MAC-Adresse. Diese Felder werden im Parser gelesen (das
Format ist ein zusammenhängender Byte-Block), aber nicht in die Anzeige- oder
Copy-Rows aufgenommen.

## Zwischenablage (Copy-Button)

Kopiert **genau die 4 Textwerte** (Temperatur, Luftfeuchtigkeit, Luftdruck,
Taupunkt) — **ohne** die Signalstärke. Format: eine Zeile pro Wert,
`Bezeichnung: Wert Einheit`. Beispiel:

```
Temperatur: 21.4 °C
Luftfeuchtigkeit: 48.5 %
Luftdruck: 1013.2 hPa
Taupunkt: 10.2 °C
```

Umsetzung: `UIPasteboard.general.string = ...`.

## Architektur

Drei kleine, klar getrennte Einheiten.

### 1. `RuuviData` (Model, `struct`)

Reine Wertestruktur mit den geparsten DF5-Feldern plus berechnetem Taupunkt.

- Felder: `temperature: Double` (°C), `humidity: Double` (%),
  `pressure: Double` (hPa), `dewPoint: Double` (°C), sowie die geparsten aber
  ungenutzten Felder (Beschleunigung, Batterie, TX, Bewegungszähler, Sequenz,
  MAC) für Vollständigkeit/spätere Nutzung.
- `var displayRows: [(label: String, value: String, unit: String)]` — die
  **einzige** Quelle für die angezeigten Textwerte **und** den Copy-Text.
  Vermeidet Duplizierung zwischen Anzeige und Zwischenablage.
- Taupunkt via **Magnus-Formel**:
  `γ = (a·T)/(b+T) + ln(RH/100)`, `Td = (b·γ)/(a−γ)` mit `a = 17.62`, `b = 243.12`.

### 2. `RuuviScanner` (BLE, `ObservableObject`)

Besitzt den `CBCentralManager` und kapselt das gesamte BLE-Verhalten.

- Startet passives Scannen (`scanForPeripherals`, kein Service-Filter, da Ruuvi
  in den Manufacturer-Advertisement-Daten sendet; `CBCentralManagerScanOptionAllowDuplicatesKey = true`
  für Echtzeit-Updates).
- In `didDiscover`: liest `CBAdvertisementDataManufacturerDataKey`, prüft auf
  Ruuvi-Hersteller-ID `0x0499` (Little-Endian erste 2 Bytes) und Format-Byte `5`.
- Wählt den Tag mit dem **stärksten RSSI** (bei mehreren gleichzeitig sichtbaren);
  bei nur einem Tag ohnehin dieser.
- Parst DF5 und published:
  - `@Published var data: RuuviData?`
  - `@Published var rssi: Int?` (für den Live-Balken)
  - `@Published var state: ScannerState` (`.scanning`, `.bluetoothOff`,
    `.unauthorized`, `.noTag`) für Hinweistexte.
- Delegate-Callbacks laufen auf interner Queue → UI-relevante Updates auf
  `@Published` erfolgen auf der Main-Queue.

### 3. `ContentView` (SwiftUI)

- Beobachtet den `RuuviScanner` via `@StateObject`.
- Rendert `data.displayRows` als Liste (Label links, `Wert Einheit` rechts).
- Rendert die Signalstärke als **Balken** (z. B. `ProgressView` oder eigenes
  `GeometryReader`-Balken-View), gespeist aus `rssi` (Mapping RSSI-dBm →
  0…1, z. B. −100 dBm = leer, −40 dBm = voll).
- Button „In Zwischenablage kopieren" → setzt `UIPasteboard.general.string`
  aus denselben `displayRows`.
- Zeigt bei fehlenden Daten / BLE-Problemen den passenden Hinweis aus `state`.

## Datenfluss

```
CoreBluetooth didDiscover (interne Queue)
  → Manufacturer-Data prüfen (0x0499, DF5)
  → RSSI vergleichen, stärksten Tag wählen
  → DF5 parsen → RuuviData (inkl. Taupunkt)
  → auf Main-Queue: @Published data / rssi setzen
  → SwiftUI rendert automatisch neu
```

## Fehler- & Randfälle

- **Kein Tag in Reichweite:** Hinweis „Suche RuuviTag…".
- **Bluetooth aus:** Hinweis „Bluetooth ist ausgeschaltet".
- **Keine Berechtigung:** Hinweis auf BLE-Berechtigung.
- **Info.plist:** `NSBluetoothAlwaysUsageDescription` gesetzt.
- **Simulator:** kein BLE → bleibt im Zustand „Suche…". Erwartet, dokumentiert.

## DF5 / RAWv2 Payload-Referenz (Parsing)

Manufacturer-Data-Bytes nach der 2-Byte-Hersteller-ID (`0x99 0x04`):

| Offset | Bytes | Feld                     | Umrechnung                          |
|--------|-------|--------------------------|-------------------------------------|
| 0      | 1     | Format = `0x05`          | Prüfen                              |
| 1      | 2     | Temperatur (int16, BE)   | × 0.005 °C                          |
| 3      | 2     | Luftfeuchte (uint16, BE) | × 0.0025 %                          |
| 5      | 2     | Luftdruck (uint16, BE)   | (+ 50000) Pa → ÷100 hPa             |
| 7      | 2     | Beschleunigung X (int16) | mg → g (ungenutzt)                  |
| 9      | 2     | Beschleunigung Y (int16) | mg → g (ungenutzt)                  |
| 11     | 2     | Beschleunigung Z (int16) | mg → g (ungenutzt)                  |
| 13     | 2     | Power-Info (uint16)      | 11 bit Batterie-mV, 5 bit TX (ungenutzt) |
| 15     | 1     | Bewegungszähler          | (ungenutzt)                         |
| 16     | 2     | Mess-Sequenznummer       | (ungenutzt)                         |
| 18     | 6     | MAC                      | (ungenutzt)                         |

Ungültige/„nicht verfügbar"-Werte laut Spec (z. B. `0x8000` bei Temperatur)
werden defensiv als fehlend behandelt.

## Projektstruktur

Neues SwiftUI-Xcode-Projekt im aktuellen Ordner:

```
ambient-ruuvi.xcodeproj
ambient-ruuvi/
  ambient_ruuviApp.swift   (@main App)
  ContentView.swift
  RuuviScanner.swift
  RuuviData.swift
  Info.plist               (NSBluetoothAlwaysUsageDescription)
  Assets.xcassets
```

## Nicht im Scope (YAGNI)

- Keine Persistenz / Historie / Charts.
- Keine Tag-Auswahl-UI, kein Pairing.
- Keine Anzeige von Beschleunigung/Batterie/TX/MAC etc.
- Kein DF3-Legacy-Format.
- Keine Hintergrund-Scans / Notifications.
