import Foundation
import SpoolDryKit

/// The latest known dryer state, written by the app into the App Group and read by widgets.
/// Contains only what the device reported (no fabricated values).
struct WidgetSnapshot: Codable, Equatable {
    var deviceName: String
    var filamentLabel: String?
    var display: DryingDisplayState
    var isConnected: Bool
    var temperatureUnit: TemperatureUnit

    static let placeholder = WidgetSnapshot(
        deviceName: "SpoolDry",
        filamentLabel: "PA-CF",
        display: DryingDisplayState(state: .drying, chamberCelsius: 67.2, humidityPercent: 18.4, targetCelsius: 70,
                                    dryingEndDate: Date().addingTimeInterval(2 * 3600 + 41 * 60), remainingSeconds: 9660,
                                    durationSeconds: 28800, progress: 0.66, updatedAt: Date()),
        isConnected: true,
        temperatureUnit: .celsius)

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: SharedConstants.appGroupID),
              let data = defaults.data(forKey: SharedConstants.widgetSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: SharedConstants.appGroupID),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: SharedConstants.widgetSnapshotKey)
    }

    static func clear() {
        UserDefaults(suiteName: SharedConstants.appGroupID)?.removeObject(forKey: SharedConstants.widgetSnapshotKey)
    }
}
