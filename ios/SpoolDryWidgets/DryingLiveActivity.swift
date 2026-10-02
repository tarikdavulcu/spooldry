import ActivityKit
import SpoolDryKit
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island. Everything shown comes from the dryer's last report.
/// While preheating no countdown is shown (the device has not started the timer yet).
struct DryingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpoolDryActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Theme.graphite.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "spooldry://dashboard"))
        } dynamicIsland: { context in
            let d = context.state.display
            let unit = context.attributes.temperatureUnit
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.filamentLabel).font(.headline).lineLimit(1)
                        Label(LocalizedStringKey(d.state.localizationKey), systemImage: d.state.symbolName)
                            .font(.caption).foregroundStyle(Theme.color(for: d.state))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        RemainingText(display: d).font(.title3.weight(.bold)).monospacedDigit()
                        Text("Remaining").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Metric(icon: "scope", value: SpoolDryFormat.temperature(d.targetCelsius, unit: unit, fractionDigits: 0), label: "Target")
                        Spacer()
                        Metric(icon: "thermometer.medium", value: SpoolDryFormat.temperature(d.chamberCelsius, unit: unit), label: "Current")
                        Spacer()
                        Metric(icon: "humidity", value: SpoolDryFormat.humidity(d.humidityPercent), label: "Humidity")
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Text(context.attributes.filamentLabel).font(.caption.weight(.semibold)).lineLimit(1)
            } compactTrailing: {
                RemainingText(display: d).font(.caption.weight(.semibold)).monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: d.state.symbolName).foregroundStyle(Theme.color(for: d.state))
            }
            .keylineTint(Theme.accent)
            .widgetURL(URL(string: "spooldry://dashboard"))
        }
    }
}

private struct RemainingText: View {
    let display: DryingDisplayState

    var body: some View {
        switch display.state {
        case .drying:
            if let end = display.dryingEndDate, end > Date() {
                Text(timerInterval: Date()...end, countsDown: true, showsHours: true)
            } else {
                Text("0:00")
            }
        case .preheating:
            Image(systemName: "thermometer.sun")
                .accessibilityLabel(Text("Preheating"))
        case .cooldown:
            Image(systemName: "wind").accessibilityLabel(Text("Cooling down"))
        case .completed:
            Image(systemName: "checkmark.seal.fill").accessibilityLabel(Text("Completed"))
        default:
            Image(systemName: display.state.symbolName)
        }
    }
}

private struct Metric: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 2) {
            Label(value, systemImage: icon).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<SpoolDryActivityAttributes>

    var body: some View {
        let d = context.state.display
        let unit = context.attributes.temperatureUnit
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.filamentLabel).font(.headline)
                    Text(context.attributes.deviceName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(LocalizedStringKey(d.state.localizationKey), systemImage: d.state.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.color(for: d.state))
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    RemainingText(display: d).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Group {
                        if d.state == .preheating {
                            Text("Heating to target – timer starts at temperature")
                        } else {
                            Text("Remaining")
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Metric(icon: "scope", value: SpoolDryFormat.temperature(d.targetCelsius, unit: unit, fractionDigits: 0), label: "Target")
                Metric(icon: "thermometer.medium", value: SpoolDryFormat.temperature(d.chamberCelsius, unit: unit), label: "Current")
                Metric(icon: "humidity", value: SpoolDryFormat.humidity(d.humidityPercent), label: "Humidity")
            }
            if let p = d.progress {
                ProgressView(value: p).tint(Theme.accent)
            }
            if !context.state.isConnected || context.isStale {
                Text("Last update \(d.updatedAt, style: .relative) ago. The dryer keeps running safely on its own.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .foregroundStyle(.white)
    }
}
