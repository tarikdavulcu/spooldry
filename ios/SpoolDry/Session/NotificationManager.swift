import Foundation
import SpoolDryKit
import UserNotifications

/// Local notifications only. They are posted when the app actually receives the device's state
/// (BLE works in the background), never on a guessed schedule.
@MainActor
final class NotificationManager {
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyOutcome(_ outcome: SessionOutcome, filament: String, deviceName: String, error: DeviceErrorCode) {
        let content = UNMutableNotificationContent()
        switch outcome {
        case .completed:
            content.title = String(localized: "Drying complete")
            content.body = String(localized: "\(filament) is dry. \(deviceName) is cooling down or finished.")
            content.sound = .default
        case .overTemperature:
            content.title = String(localized: "Over-temperature protection")
            content.body = String(localized: "\(deviceName) switched the heater off. Check the dryer before restarting.")
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        case .failed:
            content.title = String(localized: "Drying stopped by a fault")
            content.body = String(localized: String.LocalizationValue(error.localizationKey))
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        default:
            return
        }
        let request = UNNotificationRequest(identifier: "outcome-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyDryingStarted(filament: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Target temperature reached")
        content.body = String(localized: "The drying timer for \(filament) is now running.")
        let request = UNNotificationRequest(identifier: "drying-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
