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
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(row.label)
                                Spacer()
                                Text("\(row.value) \(row.unit)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            if let note = row.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
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
