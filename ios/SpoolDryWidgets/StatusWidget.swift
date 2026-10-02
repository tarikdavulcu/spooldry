import SpoolDryKit
import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), snapshot: context.isPreview ? (WidgetSnapshot.load() ?? .placeholder) : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        var refresh = now.addingTimeInterval(30 * 60)
        if let end = snapshot?.display.dryingEndDate, end > now {
            refresh = min(refresh, end.addingTimeInterval(60))  // flip to "should be done" after the timer ends
        }
        completion(Timeline(entries: [StatusEntry(date: now, snapshot: snapshot)], policy: .after(refresh)))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedConstants.widgetKind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.heroGradient }
                .widgetURL(URL(string: "spooldry://dashboard"))
        }
        .configurationDisplayName("SpoolDry")
        .description("Temperature, humidity and drying progress of your filament dryer.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StatusWidgetView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .systemSmall: SmallStatus(snapshot: s, now: entry.date)
            case .systemMedium: MediumStatus(snapshot: s, now: entry.date)
            default: LargeStatus(snapshot: s, now: entry.date)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title2)
                Text("Open SpoolDry to connect your dryer.").font(.footnote)
            }
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Building blocks

private struct ValueLine: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(label).font(.caption2).opacity(0.75)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StateLine: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.display.state.symbolName)
            Text(LocalizedStringKey(snapshot.display.state.localizationKey)).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
    }
}

private struct RemainingView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let d = snapshot.display
        if d.state == .drying, let end = d.dryingEndDate, end > now {
            Text(timerInterval: now...end, countsDown: true)
                .monospacedDigit()
        } else if d.state == .preheating {
            Text("Preheating")
        } else if d.state == .completed {
            Text("Done")
        } else {
            Text("--")
        }
    }
}

private struct UpdatedLine: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        if snapshot.display.isStale(at: now) || !snapshot.isConnected {
            Text("Last update \(snapshot.display.updatedAt, style: .relative) ago")
                .font(.caption2).opacity(0.7)
        }
    }
}

private struct SmallStatus: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StateLine(snapshot: snapshot, now: now)
            ValueLine(icon: "thermometer.medium",
                      value: SpoolDryFormat.temperature(snapshot.display.chamberCelsius, unit: snapshot.temperatureUnit),
                      label: "Temperature")
            ValueLine(icon: "humidity", value: SpoolDryFormat.humidity(snapshot.display.humidityPercent), label: "Humidity")
            Spacer(minLength: 0)
            UpdatedLine(snapshot: snapshot, now: now)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediumStatus: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.deviceName).font(.caption).opacity(0.75).lineLimit(1)
                StateLine(snapshot: snapshot, now: now)
                RemainingView(snapshot: snapshot, now: now)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("Remaining").font(.caption2).opacity(0.75)
                UpdatedLine(snapshot: snapshot, now: now)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                ValueLine(icon: "thermometer.medium",
                          value: SpoolDryFormat.temperature(snapshot.display.chamberCelsius, unit: snapshot.temperatureUnit),
                          label: "Temperature")
                ValueLine(icon: "humidity", value: SpoolDryFormat.humidity(snapshot.display.humidityPercent), label: "Humidity")
            }
        }
        .foregroundStyle(.white)
    }
}

private struct LargeStatus: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text(snapshot.deviceName).font(.headline).lineLimit(1)
                    StateLine(snapshot: snapshot, now: now)
                }
                Spacer()
                Image(systemName: "circle.circle").font(.title)
            }
            if let p = snapshot.display.progress {
                ProgressView(value: p).tint(.white)
                    .accessibilityLabel(Text("Drying progress"))
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    ValueLine(icon: "thermometer.medium",
                              value: SpoolDryFormat.temperature(snapshot.display.chamberCelsius, unit: snapshot.temperatureUnit),
                              label: "Temperature")
                    ValueLine(icon: "humidity", value: SpoolDryFormat.humidity(snapshot.display.humidityPercent), label: "Humidity")
                }
                GridRow {
                    ValueLine(icon: "scope",
                              value: SpoolDryFormat.temperature(snapshot.display.targetCelsius, unit: snapshot.temperatureUnit, fractionDigits: 0),
                              label: "Target")
                    ValueLine(icon: "circle.circle", value: snapshot.filamentLabel ?? "--", label: "Filament")
                }
            }
            HStack {
                Image(systemName: "timer")
                RemainingView(snapshot: snapshot, now: now).font(.system(.title2, design: .rounded, weight: .bold))
                Text("Remaining").font(.caption).opacity(0.75)
            }
            Spacer(minLength: 0)
            UpdatedLine(snapshot: snapshot, now: now)
        }
        .foregroundStyle(.white)
    }
}
