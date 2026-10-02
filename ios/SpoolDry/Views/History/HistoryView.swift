import Charts
import SpoolDryKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    enum Mode: Hashable { case sessions, statistics }

    @Environment(\.modelContext) private var context
    @Query(sort: \DryingSessionRecord.startedAt, order: .reverse) private var records: [DryingSessionRecord]
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue
    @State private var mode: Mode = .sessions

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("No drying sessions yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Completed, stopped and failed sessions appear here. Everything is stored only on this iPhone."))
                } else if mode == .sessions {
                    List {
                        ForEach(records) { r in
                            NavigationLink(value: r.id) { SessionRow(record: r, unit: unit) }
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(records[i]) }
                            try? context.save()
                        }
                    }
                } else {
                    StatisticsView(records: records.filter { !$0.isDemo }, unit: unit)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        Text("Sessions").tag(Mode.sessions)
                        Text("Statistics").tag(Mode.statistics)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let r = records.first(where: { $0.id == id }) { SessionDetailView(record: r, unit: unit) }
            }
        }
    }
}

struct OutcomeBadge: View {
    let outcome: SessionOutcome

    private var symbol: String {
        switch outcome {
        case .inProgress: return "hourglass"
        case .completed: return "checkmark.seal.fill"
        case .stopped: return "stop.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .overTemperature: return "thermometer.high"
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var tint: Color {
        switch outcome {
        case .completed: return Theme.success
        case .failed, .overTemperature: return Theme.danger
        case .inProgress: return Theme.heat
        default: return .secondary
        }
    }

    var body: some View {
        Label(LocalizedStringKey(outcome.localizationKey), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }
}

private struct SessionRow: View {
    let record: DryingSessionRecord
    let unit: TemperatureUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.displayName).font(.headline)
                if record.isDemo {
                    Text("Demo").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                OutcomeBadge(outcome: record.outcome)
            }
            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(SpoolDryFormat.temperature(record.targetCelsius, unit: unit, fractionDigits: 0), systemImage: "scope")
                Label(SpoolDryFormat.duration(TimeInterval(record.elapsedDryingSeconds)), systemImage: "timer")
                if let s = record.startHumidity, let e = record.endHumidity {
                    Label("\(SpoolDryFormat.humidity(s)) → \(SpoolDryFormat.humidity(e))", systemImage: "humidity")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct SessionDetailView: View {
    let record: DryingSessionRecord
    let unit: TemperatureUnit

    var body: some View {
        List {
            Section {
                HStack { Text(record.displayName).font(.title3.weight(.bold)); Spacer(); OutcomeBadge(outcome: record.outcome) }
                InfoRow(title: "Date", value: record.startedAt.formatted(date: .long, time: .shortened))
                InfoRow(title: "Dryer", value: record.deviceName)
                InfoRow(title: "Target temperature", value: SpoolDryFormat.temperature(record.targetCelsius, unit: unit, fractionDigits: 0))
                InfoRow(title: "Planned duration", value: SpoolDryFormat.duration(TimeInterval(record.durationSeconds)))
                InfoRow(title: "Drying time", value: SpoolDryFormat.duration(TimeInterval(record.elapsedDryingSeconds)))
                InfoRow(title: "Average temperature", value: SpoolDryFormat.temperature(record.averageTemperature, unit: unit))
                InfoRow(title: "Starting humidity", value: SpoolDryFormat.humidity(record.startHumidity))
                InfoRow(title: "Ending humidity", value: SpoolDryFormat.humidity(record.endHumidity))
                InfoRow(title: "Lowest humidity", value: SpoolDryFormat.humidity(record.minHumidity))
                if record.errorCode != .none {
                    LabeledContent("Fault") { Text(LocalizedStringKey(record.errorCode.localizationKey)) }
                }
                if let end = record.endHumidity, end <= record.humidityTargetPercent {
                    Label("Humidity target reached", systemImage: "checkmark.circle").foregroundStyle(Theme.success)
                }
            }
            let samples = record.samples
            if samples.count >= 2 {
                Section("Temperature & humidity") {
                    Chart {
                        ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                            if let c = s.c {
                                LineMark(x: .value("Minutes", s.t / 60), y: .value("Temperature", unit.convert(fromCelsius: c)),
                                         series: .value("Series", "t"))
                                    .foregroundStyle(Theme.heat)
                            }
                            if let h = s.h {
                                LineMark(x: .value("Minutes", s.t / 60), y: .value("Humidity", h), series: .value("Series", "h"))
                                    .foregroundStyle(Theme.moisture)
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            }
                        }
                    }
                    .frame(height: 200)
                    .accessibilityLabel(Text("Temperature and humidity chart"))
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatisticsView: View {
    let records: [DryingSessionRecord]
    let unit: TemperatureUnit

    var body: some View {
        let stats = DryingStatistics.compute(records.map(\.statInput))
        ScrollView {
            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(title: "Drying sessions", value: "\(stats.totalSessions)", systemImage: "number")
                    MetricTile(title: "Drying hours", value: String(format: "%.1f", stats.totalDryingHours), systemImage: "timer")
                    MetricTile(title: "Avg. humidity reduction",
                               value: stats.averageHumidityReduction.map { String(format: "%.0f pp", $0) } ?? "--",
                               systemImage: "humidity", tint: Theme.moisture,
                               footnote: String(localized: "Percentage points, start to end"))
                    MetricTile(title: "Most used", value: stats.mostUsedMaterial?.shortName ?? "--", systemImage: "star")
                }
                MetricTile(title: "Last drying session",
                           value: stats.lastSessionDate?.formatted(date: .abbreviated, time: .shortened) ?? "--",
                           systemImage: "calendar")
                if !stats.sessionsPerMaterial.isEmpty {
                    Card {
                        VStack(alignment: .leading) {
                            Text("Sessions per material").font(.headline)
                            Chart(stats.sessionsPerMaterial, id: \.material) { item in
                                BarMark(x: .value("Sessions", item.count), y: .value("Material", item.material.shortName))
                                    .foregroundStyle(Theme.accent)
                                    .annotation(position: .trailing) { Text("\(item.count)").font(.caption) }
                            }
                            .frame(height: CGFloat(max(1, stats.sessionsPerMaterial.count)) * 34 + 20)
                        }
                    }
                }
                Text("Demo sessions are excluded.").font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
