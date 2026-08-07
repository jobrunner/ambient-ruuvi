import Foundation
import CoreBluetooth

enum ScannerState: Equatable { case scanning, noTag, bluetoothOff, unauthorized }

@MainActor
final class RuuviScanner: NSObject, ObservableObject {
    @Published var data: RuuviData?
    @Published var rssi: Int?
    @Published var state: ScannerState = .noTag

    private var central: CBCentralManager!

    struct SeenTag {
        var data: RuuviData
        var rssi: Int
        var lastSeen: Date
    }
    // Pro-Peripheral-Tracking mit Expiry: jeder Tag aktualisiert sich live,
    // ein näherer Tag kann übernehmen, ein verschwundener Tag läuft ab.
    private var seenTags: [UUID: SeenTag] = [:]
    private let expiryInterval: TimeInterval = 10
    // Räumt abgelaufene Tags auch dann auf, wenn keine Advertisements mehr
    // eintreffen — sonst friert ein einzelner Tag, der außer Reichweite gerät,
    // die Anzeige ein.
    private var refreshTimer: Timer?

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else {
            beginScan()
        }
    }

    func stop() {
        central?.stopScan()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func beginScan() {
        guard central.state == .poweredOn else { return }
        // seenTags bewusst NICHT löschen: bei einem kurzen Wechsel in den
        // Hintergrund (und zurück) bleibt der letzte Messwert erhalten, statt
        // dass die Anzeige auf „Suche…“ zurückfällt. Verwaiste Tags räumt der
        // Expiry-Mechanismus in refresh() nach expiryInterval ohnehin auf.
        state = .scanning
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Evict aged-out tags and publish the strongest survivor, or clear the
    /// display when none remain. Runs both on each advertisement and on the timer.
    private func refresh() {
        seenTags = RuuviScanner.liveTags(from: seenTags, now: Date(), expiry: expiryInterval)
        if let strongest = RuuviScanner.strongest(in: seenTags) {
            data = strongest.data
            rssi = strongest.rssi
        } else {
            data = nil
            rssi = nil
        }
    }

    nonisolated static func liveTags(from tags: [UUID: SeenTag],
                                     now: Date,
                                     expiry: TimeInterval) -> [UUID: SeenTag] {
        let cutoff = now.addingTimeInterval(-expiry)
        return tags.filter { $0.value.lastSeen >= cutoff }
    }

    nonisolated static func strongest(in tags: [UUID: SeenTag]) -> SeenTag? {
        tags.values.max(by: { $0.rssi < $1.rssi })
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
            // Record this peripheral's latest reading, then evict + republish.
            seenTags[id] = SeenTag(data: parsed, rssi: r, lastSeen: Date())
            state = .scanning
            refresh()
        }
    }
}
