import Foundation
import CoreBluetooth

enum ScannerState: Equatable { case scanning, noTag, bluetoothOff, unauthorized }

@MainActor
final class RuuviScanner: NSObject, ObservableObject {
    @Published var data: RuuviData?
    @Published var rssi: Int?
    @Published var state: ScannerState = .noTag

    private var central: CBCentralManager!

    private struct SeenTag {
        var data: RuuviData
        var rssi: Int
        var lastSeen: Date
    }
    // Pro-Peripheral-Tracking mit Expiry: jeder Tag aktualisiert sich live,
    // ein näherer Tag kann übernehmen, ein verschwundener Tag läuft ab.
    private var seenTags: [UUID: SeenTag] = [:]
    private let expiryInterval: TimeInterval = 10

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
        seenTags.removeAll()
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
        let id = peripheral.identifier
        Task { @MainActor in
            // Update this peripheral's latest reading.
            seenTags[id] = SeenTag(data: parsed, rssi: r, lastSeen: Date())

            // Evict tags that have gone quiet, so a tag out of range stops winning.
            let cutoff = Date().addingTimeInterval(-expiryInterval)
            seenTags = seenTags.filter { $0.value.lastSeen >= cutoff }

            // Publish the strongest surviving tag; a closer tag can overtake,
            // and a single tag keeps refreshing live.
            if let strongest = seenTags.values.max(by: { $0.rssi < $1.rssi }) {
                data = strongest.data
                rssi = strongest.rssi
                state = .scanning
            }
        }
    }
}
