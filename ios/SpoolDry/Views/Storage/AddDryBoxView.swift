import SpoolDryKit
import SwiftUI
import UIKit

/// Adds a dry box: name, humidity limit and the BTHome sensor inside it (picked from sensors heard nearby).
struct AddDryBoxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var limit: Double = 20
    @State private var selectedSensorID: UUID?
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }
    private var scanner: SensorScanner { model.storage.scanner }
    private var usedSensorIDs: Set<UUID> { Set(model.storage.boxes().compactMap(\.sensorID)) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dry box") {
                    TextField("Name, e.g. Nylon box", text: $name)
                    Stepper(value: $limit, in: 10...45, step: 1) {
                        LabeledContent("Warn above") { Text(SpoolDryFormat.humidity(limit)).monospacedDigit() }
                    }
                }

                Section {
                    bluetoothNotice
                    let sensors = scanner.sortedNearby.filter { !usedSensorIDs.contains($0.id) }
                    if sensors.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Listening for BTHome sensors…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(sensors) { sensor in
                        Button { selectedSensorID = sensor.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: sensor.name).font(.headline)
                                    Text(readingText(sensor)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedSensorID == sensor.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .disabled(sensor.reading.isEncrypted)
                    }
                    Button {
                        selectedSensorID = nil
                    } label: {
                        HStack {
                            Text("No sensor (track spools only)")
                            Spacer()
                            if selectedSensorID == nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Sensor in this box")
                } footer: {
                    Text("Supported: Bluetooth hygrometers that broadcast unencrypted BTHome v2, such as Shelly BLU H&T or Xiaomi/Telink sensors running the open PVVX firmware in BTHome mode. Hold the sensor close to your iPhone to find it; the strongest signal is listed first.")
                }

                Section {
                    Button {
                        model.storage.addDemoBox()
                        dismiss()
                    } label: {
                        Label("No sensor yet? Add the Demo Dry Box", systemImage: "play.rectangle")
                    }
                }
            }
            .navigationTitle("Add Dry Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { scanner.start() }
            .onDisappear { if !model.storage.hasSensorBoxes { scanner.stop() } }
        }
    }

    @ViewBuilder
    private var bluetoothNotice: some View {
        switch scanner.availability {
        case .poweredOff:
            Label("Turn on Bluetooth in Control Center or Settings.", systemImage: "bolt.horizontal.circle")
        case .unauthorized:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Label("Allow Bluetooth for SpoolDry in Settings to read your sensors.", systemImage: "hand.raised")
            }
        default:
            EmptyView()
        }
    }

    private func readingText(_ s: NearbySensor) -> String {
        if s.reading.isEncrypted { return String(localized: "Encrypted: turn off encryption in the sensor's app to use it.") }
        var parts: [String] = []
        if let h = s.reading.humidityPercent { parts.append(SpoolDryFormat.humidity(h, fractionDigits: 1)) }
        if let c = s.reading.temperatureCelsius { parts.append(SpoolDryFormat.temperature(c, unit: unit)) }
        parts.append(String(localized: "Signal \(String(s.rssi)) dBm"))
        return parts.joined(separator: " · ")
    }

    private func save() {
        let sensor = selectedSensorID.flatMap { scanner.nearby[$0] }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        model.storage.addBox(name: trimmed, sensor: sensor, humidityLimit: limit)
        if sensor != nil {
            Task { await NotificationManager().requestAuthorizationIfNeeded() }
        }
        dismiss()
    }
}
