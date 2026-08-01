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
