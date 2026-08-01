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
