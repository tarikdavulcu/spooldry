import Charts
import SpoolDryKit
import SwiftData
import SwiftUI

/// Filament storage: dry boxes watched by Bluetooth hygrometers, and the spool inventory with
/// an estimate of which spools need drying before the next print.
struct StorageView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: [SortDescriptor(\DryBox.sortIndex), SortDescriptor(\DryBox.createdAt)]) private var boxes: [DryBox]
    @Query(sort: \Spool.createdAt) private var spools: [Spool]
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue
    @State private var showAddBox = false
    @State private var editingSpool: Spool?
    @State private var addingSpool = false

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if boxes.isEmpty && spools.isEmpty {
                        StorageIntroCard(onAddBox: addBoxTapped, onDemo: { model.storage.addDemoBox() })
                    }

                    if !boxes.isEmpty {
                        sectionHeader("Dry boxes")
                        ForEach(boxes) { box in
                            NavigationLink(value: box.id) {
                                DryBoxCard(box: box, unit: unit, spoolCount: spools.filter { $0.boxID == box.id }.count)
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: addBoxTapped) {
                            Label("Add Dry Box", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }

                    sectionHeader("Spools")
                    if spools.isEmpty {
                        Card {
                            Text("Add the spools you own to see which ones need drying before your next print.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(sortedSpools) { spool in
                            Button { editingSpool = spool } label: {
                                SpoolRow(spool: spool, box: boxes.first { $0.id == spool.boxID })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { addingSpool = true } label: {
                        Label("Add Spool", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Text("Spool condition is an estimate from each material's typical moisture sensitivity and the humidity your sensors reported since the spool was last dried. Dry before critical prints.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .spoolDryBackground()
            .navigationTitle("Storage")
            .navigationDestination(for: UUID.self) { id in
                if let box = boxes.first(where: { $0.id == id }) { DryBoxDetailView(box: box) }
            }
            .sheet(isPresented: $showAddBox) { AddDryBoxView() }
            .sheet(item: $editingSpool) { spool in SpoolEditorView(spool: spool) }
            .sheet(isPresented: $addingSpool) { SpoolEditorView(spool: nil) }
            .onAppear { if boxes.contains(where: { $0.sensorID != nil && !$0.isDemo }) { model.storage.scanner.start() } }
            .onDisappear { model.storage.scanner.stop() }
        }
    }

    /// Spools that need drying first.
    private var sortedSpools: [Spool] {
        let order: [SpoolCondition: Int] = [.needsDrying: 0, .watch: 1, .unknown: 2, .dry: 3]
        func rank(_ s: Spool) -> Int {
            let box = boxes.first { $0.id == s.boxID }
            return order[s.condition(in: box)] ?? 9
        }
        return spools.sorted { lhs, rhs in
            let l = rank(lhs), r = rank(rhs)
            return l == r ? lhs.createdAt < rhs.createdAt : l < r
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.title3.weight(.bold)).padding(.top, 4)
    }

    private func addBoxTapped() {
        let realBoxes = boxes.filter { !$0.isDemo }.count
        if model.store.hasLifetime || realBoxes < StorageLimits.freeDryBoxes {
            showAddBox = true
        } else {
            model.showPaywall = true
        }
    }
}

enum StorageLimits {
    /// Dry boxes with a real sensor included for free; SpoolDry Lifetime removes the limit.
    static let freeDryBoxes = 2
}

private struct StorageIntroCard: View {
    let onAddBox: () -> Void
    let onDemo: () -> Void

    var body: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "archivebox").font(.largeTitle).foregroundStyle(Theme.moisture)
                Text("Keep stored filament dry").font(.title2.weight(.bold))
                Text("Put a Bluetooth thermo-hygrometer that broadcasts in the open BTHome format (for example Shelly BLU H&T, or Xiaomi sensors with PVVX firmware) into your filament box. SpoolDry reads it directly, without pairing, account or cloud, and warns you when the box gets too humid.")
                    .foregroundStyle(.secondary)
                Button(action: onAddBox) { Label("Add Dry Box", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Try the Demo Dry Box", action: onDemo)
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct DryBoxCard: View {
    let box: DryBox
    let unit: TemperatureUnit
    let spoolCount: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: box.name).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    BoxStatusBadge(box: box)
                }
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading) {
                        Text(SpoolDryFormat.humidity(box.lastHumidity, fractionDigits: 1))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(box.isAboveLimit ? Theme.danger : Theme.moisture)
                        Text("Humidity").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text(SpoolDryFormat.temperature(box.lastTemperature, unit: unit))
                            .font(.title3.weight(.semibold)).monospacedDigit()
                        Text("Temperature").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                BoxSparkline(samples: box.samples, limit: box.humidityLimit)
                    .frame(height: 54)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(String(localized: "Limit \(SpoolDryFormat.humidity(box.humidityLimit))"))
        let count = spoolCount
        parts.append(String(localized: "\(count) spools"))
        if let b = box.lastBattery { parts.append(String(localized: "Battery \(String(b))%")) }
        return parts.joined(separator: " · ")
    }
}

struct BoxStatusBadge: View {
    let box: DryBox

    var body: some View {
        let (key, icon, color): (LocalizedStringKey, String, Color) = {
            if box.sensorID == nil { return ("No sensor", "sensor", .secondary) }
            if !box.isFresh() { return ("No recent data", "antenna.radiowaves.left.and.right.slash", .secondary) }
            if box.isAboveLimit { return ("Too humid", "drop.triangle", Theme.danger) }
            return ("Dry", "checkmark.seal", Theme.success)
        }()
        Label(key, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Last 24 hours of box humidity with the limit as a dashed line.
struct BoxSparkline: View {
    let samples: [HumiditySample]
    let limit: Double

    var body: some View {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let recent = samples.filter { $0.t >= cutoff }
        if recent.count < 2 {
            Text("Collecting data…").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            Chart {
                ForEach(recent, id: \.t) { s in
                    LineMark(x: .value("Time", s.t), y: .value("Humidity", s.h))
                        .foregroundStyle(Theme.moisture)
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Limit", limit))
                    .foregroundStyle(Theme.danger.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...max(40, (recent.map(\.h).max() ?? 0) + 5))
            .accessibilityHidden(true)
        }
    }
}

struct SpoolRow: View {
    let spool: Spool
    let box: DryBox?

    var body: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "circle.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: spool.title.isEmpty ? spool.material.shortName : spool.title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                ConditionBadge(condition: spool.condition(in: box))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        parts.append(box?.name ?? String(localized: "Room air"))
        if let d = spool.lastDriedAt {
            parts.append(String(localized: "Dried \(d.formatted(.relative(presentation: .named)))"))
        }
        if let g = spool.remainingGrams { parts.append("\(g) g") }
        return parts.joined(separator: " · ")
    }
}

struct ConditionBadge: View {
    let condition: SpoolCondition

    var body: some View {
        let (icon, color): (String, Color) = {
            switch condition {
            case .dry: return ("checkmark.seal", Theme.success)
            case .watch: return ("eye", .orange)
            case .needsDrying: return ("flame", Theme.danger)
            case .unknown: return ("questionmark.circle", .secondary)
            }
        }()
        Label(LocalizedStringKey(condition.localizationKey), systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
