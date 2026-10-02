import SpoolDryKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue
    @AppStorage(SettingsKeys.liveActivities) private var liveActivities = true
    @AppStorage(SettingsKeys.notifications) private var notifications = true
    @AppStorage(SettingsKeys.retentionDays) private var retentionDays = 90
    @AppStorage(SettingsKeys.onboardingDone) private var onboardingDone = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.store.hasLifetime {
                        Label("SpoolDry Lifetime is active. Thank you!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.success)
                    } else {
                        LabeledContent("Free drying sessions left") {
                            Text("\(model.sessions.remainingFreeSessions) / \(FreeTierPolicy.freeSessionLimit)").monospacedDigit()
                        }
                        Button("Get SpoolDry Lifetime") { model.showPaywall = true }
                    }
                    Button("Restore Purchases") { Task { await model.store.restore() } }
                } header: {
                    Text("SpoolDry Lifetime")
                }

                Section("Units") {
                    Picker("Temperature", selection: $unitRaw) {
                        Text("Celsius (°C)").tag(TemperatureUnit.celsius.rawValue)
                        Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit.rawValue)
                    }
                }

                Section {
                    Toggle("Live Activity while drying", isOn: $liveActivities)
                    Toggle("Notifications", isOn: $notifications)
                } header: {
                    Text("Lock Screen & alerts")
                } footer: {
                    Text("Live Activities and notifications show only what your dryer reported over Bluetooth. If the iPhone is out of range, the dryer keeps running safely and SpoolDry catches up on reconnect.")
                }

                Section {
                    Picker("Keep chart data", selection: $retentionDays) {
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                    Button("Try the Demo Dryer") {
                        model.addDemoDevice()
                        model.selectedTab = .dashboard
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("All data stays on this iPhone: dryers, drying history, profiles and settings. No account, no cloud, no tracking. Session summaries are kept; detailed chart samples are removed after the selected period.")
                }

                Section("Safety") {
                    Label("SpoolDry hardware is a DIY/hobby project and is not certified. Never bypass the thermal fuse or thermostat, and do not leave a prototype unattended.",
                          systemImage: "exclamationmark.shield")
                        .font(.footnote)
                }

                Section("About") {
                    Link("Website", destination: SharedConstants.websiteURL)
                    Link("Build guide & firmware", destination: SharedConstants.hardwareGuideURL)
                    Link("Support", destination: SharedConstants.supportURL)
                    Link("Privacy Policy", destination: SharedConstants.privacyURL)
                    Button("Show Introduction Again") { onboardingDone = false }
                    LabeledContent("Version") { Text(appVersion) }
                    LabeledContent("BLE protocol") { Text(verbatim: "v\(SpoolDryProtocol.protocolVersion)") }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let b = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
        return "\(v) (\(b))"
    }
}
