import Charts
import SpoolDryKit
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.temperatureUnit) private var unitRaw = TemperatureUnit.preferred().rawValue
    @State private var showStart = false
    @State private var actionError: String?
    @State private var isBusy = false

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let link = model.activeLink {
                        DeviceHeader(link: link)
                        HeroStatusCard(link: link, unit: unit)
                        metrics(link)
                        if let status = link.status, status.state == .error || status.state == .overTemperature {
                            FaultCard(status: status) { await perform { try await model.sessions.reset(on: link) } }
                        }
                        if link.needsPairing || link.lastErrorMessage != nil {
                            NoticeCard(text: link.lastErrorMessage ?? "", systemImage: "lock.shield")
                        }
                        primaryAction(link)
                        LiveChartCard(points: model.sessions.liveSeries[link.id] ?? [], unit: unit)
                        quickLinks
                    } else {
                        EmptyDeviceCard()
                    }
                }
                .padding()
            }
            .spoolDryBackground()
            .navigationTitle("SpoolDry")
            .toolbar {
                if model.sortedLinks.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) { devicePicker }
                }
            }
            .sheet(isPresented: $showStart) {
                if let link = model.activeLink { StartDryingView(link: link) }
            }
            .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    private func metrics(_ link: DeviceLink) -> some View {
        let s = link.status
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "Temperature", value: SpoolDryFormat.temperature(s?.chamberCelsius, unit: unit),
                       systemImage: "thermometer.medium", tint: Theme.heat)
            MetricTile(title: "Humidity", value: SpoolDryFormat.humidity(s?.humidityPercent),
                       systemImage: "humidity", tint: Theme.moisture, footnote: String(localized: "Relative humidity"))
            MetricTile(title: "Target", value: s.map { SpoolDryFormat.temperature($0.targetCelsius, unit: unit, fractionDigits: 0) } ?? "--",
                       systemImage: "scope")
            MetricTile(title: "Filament", value: filamentLabel(link), systemImage: "circle.circle")
        }
    }

    private func filamentLabel(_ link: DeviceLink) -> String {
        guard let s = link.status, s.isSessionActive || s.state == .completed else { return "--" }
        return s.material.shortName
    }

    @ViewBuilder
    private func primaryAction(_ link: DeviceLink) -> some View {
        let state = link.effectiveState
        if state == .preheating || state == .drying {
            Button {
                Task { await perform { try await model.sessions.stop(on: link) } }
            } label: {
                Label("Stop Drying", systemImage: "stop.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
            .disabled(isBusy)
        } else {
            VStack(spacing: 8) {
                Button {
                    startTapped(link)
                } label: {
                    Label("Start Drying", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!link.isReady || state == .cooldown || state == .error || state == .overTemperature || isBusy)
                freeTierNote(link)
            }
        }
    }

    @ViewBuilder
    private func freeTierNote(_ link: DeviceLink) -> some View {
        if link.isDemo {
            Text("Demo sessions are simulated and do not use your free sessions.")
                .font(.footnote).foregroundStyle(.secondary)
        } else if !model.store.hasLifetime {
            Text("Free drying sessions left: \(model.sessions.remainingFreeSessions)")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func startTapped(_ link: DeviceLink) {
        if case .paywall = model.sessions.decision(for: link) {
            model.showPaywall = true
        } else {
            showStart = true
        }
    }

    private var quickLinks: some View {
        HStack(spacing: 12) {
            quickLink("Profiles", "list.bullet.rectangle", .profiles)
            quickLink("History", "clock.arrow.circlepath", .history)
            quickLink("Device", "cpu", .device)
            quickLink("Settings", "gearshape", .settings)
        }
    }

    private func quickLink(_ title: LocalizedStringKey, _ icon: String, _ tab: AppTab) -> some View {
        Button { model.selectedTab = tab } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var devicePicker: some View {
        Menu {
            Picker("Dryer", selection: Binding(get: { model.activeLink?.id }, set: { model.activeDeviceID = $0 })) {
                ForEach(model.sortedLinks) { link in
                    Text(link.name).tag(Optional(link.id))
                }
            }
        } label: {
            Label("Switch dryer", systemImage: "arrow.left.arrow.right.circle")
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do { try await work() } catch { actionError = error.localizedDescription }
    }
}

// MARK: - Subviews

private struct DeviceHeader: View {
    let link: DeviceLink

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(link.name).font(.title3.weight(.semibold))
                if link.isDemo {
                    Text("Simulated demo device").font(.caption).foregroundStyle(.secondary)
                } else if let fw = link.info?.firmwareVersion {
                    Text("Firmware \(fw)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            StateBadge(state: link.effectiveState)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HeroStatusCard: View {
    let link: DeviceLink
    let unit: TemperatureUnit

    var body: some View {
        let status = link.status
        let duration = link.sessionInfo?.durationSeconds ?? status?.remainingSeconds ?? 0
        let display = status.map { DryingDisplayState.from(status: $0, durationSeconds: duration, receivedAt: link.lastStatusAt ?? Date()) }
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.heroGradient)
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: display?.progress, tint: Theme.color(for: link.effectiveState))
                    VStack(spacing: 2) {
                        Image(systemName: link.effectiveState.symbolName).font(.title2)
                        if let end = display?.dryingEndDate, link.effectiveState == .drying {
                            Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                        } else {
                            Text(LocalizedStringKey(link.effectiveState.localizationKey))
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .padding(20)
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Drying status").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    Text(LocalizedStringKey(link.effectiveState.localizationKey))
                        .font(.title2.weight(.bold))
                    detail(display: display)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func detail(display: DryingDisplayState?) -> some View {
        switch link.effectiveState {
        case .preheating:
            Text("Heating to target. The drying timer starts at temperature.")
                .font(.footnote).foregroundStyle(.white.opacity(0.8))
        case .drying:
            if let end = display?.dryingEndDate {
                Text("Ends at \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8))
            }
        case .cooldown:
            Text("Heater off. Fan is cooling the chamber.").font(.footnote).foregroundStyle(.white.opacity(0.8))
        case .completed:
            Text("Your filament is dry. Store it sealed with desiccant.").font(.footnote).foregroundStyle(.white.opacity(0.8))
        case .disconnected:
            Text("Not connected. A running session continues safely on the dryer.").font(.footnote).foregroundStyle(.white.opacity(0.8))
        case .connecting:
            Text("Connecting…").font(.footnote).foregroundStyle(.white.opacity(0.8))
        default:
            Text("Ready").font(.footnote).foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct FaultCard: View {
    let status: DeviceStatus
    let reset: () async -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(LocalizedStringKey(status.state.localizationKey), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.danger)
                Text(LocalizedStringKey(status.error.localizationKey))
                    .font(.subheadline)
                Text("The heater is off. Inspect the dryer, then reset the fault.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reset Fault") { Task { await reset() } }
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct NoticeCard: View {
    let text: String
    let systemImage: String

    var body: some View {
        Card {
            Label(text, systemImage: systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyDeviceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(Theme.accent)
                Text("Connect your SpoolDry dryer").font(.title2.weight(.bold))
                Text("Switch on your ESP32 dryer and keep your iPhone nearby. SpoolDry talks to it directly over Bluetooth. No account, no cloud.")
                    .foregroundStyle(.secondary)
                Button {
                    model.showDeviceSetup = true
                } label: {
                    Label("Set Up Dryer", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Try the Demo Dryer") { model.addDemoDevice() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct LiveChartCard: View {
    let points: [SessionCoordinator.LivePoint]
    let unit: TemperatureUnit

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 3 hours").font(.headline)
                if points.count < 2 {
                    Text("The chart fills in while the dryer is connected.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    Chart {
                        ForEach(points) { p in
                            if let c = p.celsius {
                                LineMark(x: .value("Time", p.date), y: .value("Temperature", unit.convert(fromCelsius: c)),
                                         series: .value("Series", "temperature"))
                                    .foregroundStyle(Theme.heat)
                            }
                            if let h = p.humidity {
                                LineMark(x: .value("Time", p.date), y: .value("Humidity", h), series: .value("Series", "humidity"))
                                    .foregroundStyle(Theme.moisture)
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            }
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .frame(height: 160)
                    HStack(spacing: 16) {
                        Label("Temperature (\(unit.symbol))", systemImage: "line.diagonal").foregroundStyle(Theme.heat)
                        Label("Humidity (%)", systemImage: "line.diagonal").foregroundStyle(Theme.moisture)
                    }
                    .font(.caption)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Temperature and humidity chart"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        guard let last = points.last else { return "" }
        return "\(SpoolDryFormat.temperature(last.celsius, unit: unit)), \(SpoolDryFormat.humidity(last.humidity))"
    }
}
