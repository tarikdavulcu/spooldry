import ActivityKit
import Foundation
import SpoolDryKit

/// Live Activity for an active drying session (Lock Screen + Dynamic Island).
struct SpoolDryActivityAttributes: ActivityAttributes {
    /// Dynamic data. Mirrors the device's reported state only.
    struct ContentState: Codable, Hashable {
        var display: DryingDisplayState
        var isConnected: Bool
    }

    var filamentLabel: String
    var materialRaw: UInt8
    var deviceName: String
    /// CoreBluetooth peripheral identifier (UUID string) so multiple dryers never mix up.
    var deviceID: String
    var deviceSessionId: UInt32
    var temperatureUnitRaw: String

    var temperatureUnit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
}
