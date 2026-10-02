import SwiftUI
import SpoolDryKit

/// SpoolDry visual language: graphite surfaces, teal accent, amber heat, blue moisture.
/// State is always communicated with text + SF Symbol, never color alone.
enum Theme {
    static let accent = Color("AccentColor")
    static let heat = Color(red: 1.00, green: 0.60, blue: 0.20)
    static let moisture = Color(red: 0.31, green: 0.66, blue: 0.95)
    static let success = Color(red: 0.20, green: 0.78, blue: 0.47)
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.27)
    static let graphite = Color(red: 0.07, green: 0.08, blue: 0.10)

    static func color(for state: DeviceState) -> Color {
        switch state {
        case .preheating: return heat
        case .drying: return Color(red: 0.98, green: 0.75, blue: 0.25)
        case .cooldown: return moisture
        case .completed: return success
        case .error, .overTemperature: return danger
        case .connected, .idle: return accent
        case .disconnected, .connecting: return .secondary
        }
    }

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.09, green: 0.33, blue: 0.36), Color(red: 0.06, green: 0.10, blue: 0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}
