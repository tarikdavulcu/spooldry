import SpoolDryKit
import SwiftData
import SwiftUI

/// Choose a profile, adjust temperature / duration / humidity target, then start.
/// The session only counts once the dryer acknowledges START_SESSION.
struct StartDryingView: View {
    let link: DeviceLink

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomFilamentProfile.createdAt) private var customProfiles: [CustomFilamentProfile]
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue

    @State private var selectedProfileID: UUID? = FilamentProfile.builtIns.first?.id
    @State private var targetCelsius: Double = 50
    @State private var hours: Int = 6
    @State private var minutes: Int = 0
    @State private var humidityTarget: Double = 20
    @State private var fanMode: FanMode = .auto
    @State private var isStarting = false
    @State private var errorMessage: String?

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }

    private var allProfiles: [FilamentProfile] { FilamentProfile.builtIns + customProfiles.map(\.profile) }
    private var selectedProfile: FilamentProfile? { allProfiles.first { $0.id == selectedProfileID } }
    private var guidance: FilamentGuidance? { selectedProfile.flatMap { FilamentDatabase.guidance(for: $0.material) } }
    private var durationSeconds: UInt32 { UInt32(hours * 3600 + minutes * 60) }
    private var durationValid: Bool {
        durationSeconds >= SpoolDryProtocol.minDurationSec && durationSeconds <= SpoolDryProtocol.maxDurationSec
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Filament") {
                    Picker("Profile", selection: $selectedProfileID) {
                        Section("Typical guidance") {
                            ForEach(FilamentProfile.builtIns) { p in Text(p.name).tag(Optional(p.id)) }
                        }
                        if !customProfiles.isEmpty {
                            Section("My profiles") {
                                ForEach(customProfiles.map(\.profile)) { p in
                                    Text(p.brand.isEmpty ? p.name : "\(p.brand) \(p.name)").tag(Optional(p.id))
                                }
                            }
                        }
                    }
                    if let guidance { GuidanceSummary(guidance: guidance, unit: unit) }
                }

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Temperature") {
                            Text(SpoolDryFormat.temperature(targetCelsius, unit: unit, fractionDigits: 0)).monospacedDigit()
                        }
                        Slider(value: $targetCelsius, in: link.minTargetCelsius...link.maxTargetCelsius, step: 1) {
                            Text("Temperature")
                        }
                        .accessibilityValue(Text(SpoolDryFormat.temperature(targetCelsius, unit: unit, fractionDigits: 0)))
                    }
                    Stepper(value: $hours, in: 0...48) {
                        LabeledContent("Hours") { Text("\(hours)").monospacedDigit() }
                    }
                    Stepper(value: $minutes, in: 0...45, step: 15) {
                        LabeledContent("Minutes") { Text("\(minutes)").monospacedDigit() }
                    }
                    if !durationValid {
                        Text("Choose between 15 minutes and 48 hours.").font(.footnote).foregroundStyle(Theme.danger)
                    }
                    Stepper(value: $humidityTarget, in: 5...40, step: 1) {
                        LabeledContent("Humidity target") { Text("< \(Int(humidityTarget))% RH").monospacedDigit() }
                    }
                    Picker("Fan", selection: $fanMode) {
                        Text("Automatic").tag(FanMode.auto)
                        Text("Always on").tag(FanMode.on)
                    }
                } header: {
                    Text("Drying settings")
                } footer: {
                    Text("Limits come from your dryer: \(SpoolDryFormat.temperature(link.minTargetCelsius, unit: unit, fractionDigits: 0)) to \(SpoolDryFormat.temperature(link.maxTargetCelsius, unit: unit, fractionDigits: 0)). The fan always runs while heating.")
                }

                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger) }
                }

                Section {
                    Button {
                        Task { await start() }
                    } label: {
                        if isStarting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Start Drying").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowBackground(Color.clear)
                    .disabled(isStarting || !durationValid || !link.isReady)
                } footer: {
                    Text("Typical starting guidance, not a manufacturer requirement. Always check your filament's data sheet.")
                }
            }
            .navigationTitle("Start Drying")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: selectedProfileID, initial: true) { _, _ in applyProfile() }
        }
    }

    private func applyProfile() {
        guard let p = selectedProfile else { return }
        targetCelsius = min(max(p.temperature.rounded(), link.minTargetCelsius), link.maxTargetCelsius)
        let total = Int(p.duration)
        hours = min(48, total / 3600)
        minutes = ((total % 3600) / 60 / 15) * 15
        humidityTarget = p.humidityTarget
    }

    private func start() async {
        guard let p = selectedProfile else { return }
        errorMessage = nil
        isStarting = true
        defer { isStarting = false }
        let plan = DryingPlan(material: p.material, filamentName: p.brand.isEmpty ? p.name : "\(p.brand) \(p.name)",
                              brand: p.brand, profileID: p.id, targetCelsius: targetCelsius, durationSeconds: durationSeconds,
                              humidityTargetPercent: humidityTarget, fanMode: fanMode)
        do {
            try await model.sessions.start(plan: plan, on: link)
            dismiss()
        } catch SessionCoordinator.StartError.paywallRequired {
            dismiss()
            model.showPaywall = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GuidanceSummary: View {
    let guidance: FilamentGuidance
    let unit: TemperatureUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Typical starting guidance").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(SpoolDryFormat.temperature(guidance.temperatureRange.lowerBound, unit: unit, fractionDigits: 0))–\(SpoolDryFormat.temperature(guidance.temperatureRange.upperBound, unit: unit, fractionDigits: 0)) · \(Int(guidance.durationRangeHours.lowerBound))–\(Int(guidance.durationRangeHours.upperBound)) h")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Label {
                Text(LocalizedStringKey(guidance.sensitivity.localizationKey))
            } icon: {
                Image(systemName: "drop.degreesign")
            }
            .font(.footnote)
            ForEach(guidance.warningKeys, id: \.self) { key in
                Label(LocalizedStringKey(key), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
