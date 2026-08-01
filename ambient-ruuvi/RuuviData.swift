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
