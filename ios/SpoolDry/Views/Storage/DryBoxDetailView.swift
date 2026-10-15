import Charts
import SpoolDryKit
import SwiftData
import SwiftUI

struct DryBoxDetailView: View {
    @Bindable var box: DryBox
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Spool.createdAt) private var allSpools: [Spool]
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue
    @State private var range: ChartRange = .day
    @State private var confirmDelete = false

    enum ChartRange: Hashable { case day, week }

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }
    private var spools: [Spool] { allSpools.filter { $0.boxID == box.id } }

    var body: some View {
        List {
            Section {
                HStack {
                    MetricTile(title: "Humidity", value: SpoolDryFormat.humidity(box.lastHumidity, fractionDigits: 1),
                               systemImage: "humidity", tint: box.isAboveLimit ? Theme.danger : Theme.moisture)
                    MetricTile(title: "Temperature", value: SpoolDryFormat.temperature(box.lastTemperature, unit: unit),
                               systemImage: "thermometer.medium", tint: Theme.heat)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if let seen = box.lastSeenAt {
                    LabeledContent("Last reading") { Text(seen.formatted(.relative(presentation: .named))) }
                }
                if let b = box.lastBattery {
                    LabeledContent("Sensor battery") { Text(verbatim: "\(b) %").monospacedDigit() }
                }
            } header: {
                BoxStatusBadge(box: box).textCase(nil)
            }

            Section {
                Picker("Range", selection: $range) {
                    Text("24 hours").tag(ChartRange.day)
                    Text("7 days").tag(ChartRange.week)
                }
                .pickerStyle(.segmented)
                humidityChart.frame(height: 200)
            } header: {
                Text("Humidity history")
            } footer: {
                Text("The dashed line is this box's warning limit. SpoolDry records readings while the app is open; gaps mean no reading was received.")
            }

            Section("Settings") {
                TextField("Name", text: $box.name)
                Stepper(value: $box.humidityLimit, in: 10...45, step: 1) {
                    LabeledContent("Warn above") { Text(SpoolDryFormat.humidity(box.humidityLimit)).monospacedDigit() }
                }
                LabeledContent("Sensor") { Text(verbatim: box.sensorName.isEmpty ? "–" : box.sensorName) }
            }

            Section("Spools in this box") {
                if spools.isEmpty {
                    Text("Assign spools to this box when you add or edit them.").foregroundStyle(.secondary)
                }
                ForEach(spools) { spool in
                    HStack {
                        Text(verbatim: spool.title)
                        Spacer()
                        ConditionBadge(condition: spool.condition(in: box))
                    }
                }
            }

            Section {
                Button("Delete Dry Box", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(box.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this dry box? Its spools stay in your inventory.", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete Dry Box", role: .destructive) {
                model.storage.delete(box)
                dismiss()
            }
        }
        .onDisappear { try? model.context.save() }
    }

    @ViewBuilder
    private var humidityChart: some View {
        let cutoff = Date().addingTimeInterval(range == .day ? -24 * 3600 : -7 * 86400)
        let data = box.samples.filter { $0.t >= cutoff }
        if data.count < 2 {
            Text("Collecting data…").foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(data, id: \.t) { s in
                    AreaMark(x: .value("Time", s.t), y: .value("Humidity", s.h))
                        .foregroundStyle(Theme.moisture.opacity(0.18))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", s.t), y: .value("Humidity", s.h))
                        .foregroundStyle(Theme.moisture)
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Limit", box.humidityLimit))
                    .foregroundStyle(Theme.danger.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYScale(domain: 0...max(40, (data.map(\.h).max() ?? 0) + 5))
            .chartYAxis { AxisMarks(position: .leading) }
        }
    }
}
