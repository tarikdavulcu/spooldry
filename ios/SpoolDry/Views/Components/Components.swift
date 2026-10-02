import SpoolDryKit
import SwiftUI

/// Glass-style card used across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// A single metric (temperature, humidity, ...). Value and label are read together by VoiceOver.
struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    var tint: Color = .primary
    var footnote: String? = nil

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// State badge: icon + text (never color alone).
struct StateBadge: View {
    let state: DeviceState

    var body: some View {
        Label {
            Text(LocalizedStringKey(state.localizationKey))
        } icon: {
            Image(systemName: state.symbolName)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.color(for: state).opacity(0.18), in: Capsule())
        .foregroundStyle(Theme.color(for: state))
        .accessibilityLabel(Text("Status"))
        .accessibilityValue(Text(LocalizedStringKey(state.localizationKey)))
    }
}

/// Progress ring that only renders real progress; with `progress == nil` it shows an indeterminate track.
struct ProgressRing: View {
    let progress: Double?
    let tint: Color
    var lineWidth: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: progress)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(tint.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.black)
    }
}

struct InfoRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Applies the app's dark graphite background.
    func spoolDryBackground() -> some View {
        background(
            ZStack {
                Theme.graphite
                RadialGradient(colors: [Theme.accent.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            }
            .ignoresSafeArea()
        )
    }
}
