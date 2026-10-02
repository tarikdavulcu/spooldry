import SpoolDryKit
import SwiftUI

struct DevicesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.sortedLinks.isEmpty {
                    Section {
                        Text("No dryer set up yet.").foregroundStyle(.secondary)
                    }
                }
                Section("My dryers") {
                    ForEach(model.sortedLinks) { link in
                        NavigationLink(value: link.id) {
                            HStack {
                                Image(systemName: link.isDemo ? "play.rectangle" : "cpu")
                                    .frame(width: 28)
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading) {
                                    Text(link.name).font(.headline)
                                    Text(LocalizedStringKey(link.effectiveState.localizationKey))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.activeLink?.id == link.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                        .accessibilityLabel(Text("Shown on dashboard"))
                                }
                            }
                        }
                    }
                    Button {
                        if model.canAddAnotherDevice { model.showDeviceSetup = true } else { model.showPaywall = true }
                    } label: {
                        Label("Add Dryer", systemImage: "plus")
                    }
                    if !model.store.hasLifetime {
                        Text("The free version supports one dryer. SpoolDry Lifetime adds multiple dryers.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Link(destination: SharedConstants.hardwareGuideURL) {
                        Label("Build guide, wiring & firmware", systemImage: "wrench.and.screwdriver")
                    }
                }
            }
            .navigationTitle("Device")
            .navigationDestination(for: UUID.self) { id in
                if let link = model.ble.link(for: id) { DeviceDetailView(link: link) }
            }
        }
    }
}

struct DeviceDetailView: View {
    let link: DeviceLink
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renaming = false
    @State private var message: String?
    @State private var confirmForget = false

    var body: some View {
        List {
            Section {
                LabeledContent("Name") { Text(link.name) }
                Button("Rename") {
                    newName = link.name
                    renaming = true
                }
                LabeledContent("Status") { Text(LocalizedStringKey(link.effectiveState.localizationKey)) }
                if model.activeLink?.id != link.id {
                    Button("Show on Dashboard") { model.activeDeviceID = link.id }
                }
            }
            Section("Device information") {
                InfoRow(title: "Firmware", value: link.info?.firmwareVersion ?? "--")
                InfoRow(title: "BLE protocol", value: link.info.map { "v\($0.protocolVersion)" } ?? "--")
                InfoRow(title: "Hardware revision", value: link.info.map { "\($0.hardwareRevision)" } ?? "--")
                InfoRow(title: "Device ID", value: link.info?.deviceId.hexString.uppercased() ?? "--")
                InfoRow(title: "Maximum temperature", value: link.info.map { String(format: "%.0f °C", $0.maxTargetCelsius) } ?? "--")
                if let info = link.info {
                    LabeledContent("Safety features") {
                        Text(capabilities(info.capabilities)).multilineTextAlignment(.trailing)
                    }
                    if info.resetCause.isUnexpected {
                        Label("The dryer restarted unexpectedly. Any running session was stopped for safety.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if info.lastFault != .none {
                        LabeledContent("Last fault") { Text(LocalizedStringKey(info.lastFault.localizationKey)) }
                    }
                }
                if let s = link.status {
                    InfoRow(title: "Heater outlet", value: SpoolDryFormat.temperature(s.heaterCelsius, unit: .celsius))
                    InfoRow(title: "Fan", value: s.flags.contains(.fanOn) ? "\(s.fanRPM) rpm" : "–")
                    InfoRow(title: "Uptime", value: SpoolDryFormat.duration(TimeInterval(s.uptimeSeconds)))
                }
            }
            Section("Controls") {
                Button {
                    Task { await run { try await link.send(.identify) } }
                } label: { Label("Blink Status LED", systemImage: "lightbulb.max") }
                Picker("Fan mode", selection: Binding(get: { link.status?.fanMode ?? .auto }, set: { mode in
                    Task { await run { try await link.send(.setFanMode(mode)) } }
                })) {
                    Text("Automatic").tag(FanMode.auto)
                    Text("Always on").tag(FanMode.on)
                    Text("Off when idle").tag(FanMode.off)
                }
                .disabled(!link.isReady)
            }
            Section {
                Label("Firmware 1.0 is updated over USB. Wireless (BLE OTA) updates are prepared in the firmware layout but not available yet.",
                      systemImage: "arrow.down.circle")
                    .font(.footnote)
                Link("Firmware & flashing guide", destination: SharedConstants.hardwareGuideURL)
            } header: {
                Text("Firmware updates")
            }
            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            Section {
                Button("Forget Dryer", role: .destructive) { confirmForget = true }
            }
        }
        .navigationTitle(link.name)
        .alert("Rename Dryer", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { Task { await run { try await model.rename(link: link, to: newName) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Forget this dryer?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget Dryer", role: .destructive) {
                model.forget(id: link.id)
                dismiss()
            }
        } message: {
            Text("History stays on this iPhone. You can set the dryer up again at any time.")
        }
    }

    private func capabilities(_ c: DeviceCapabilities) -> String {
        var parts: [String] = []
        if c.contains(.safetyRelay) { parts.append(String(localized: "Safety relay")) }
        if c.contains(.heaterNtc) { parts.append(String(localized: "Heater sensor")) }
        if c.contains(.fanTach) { parts.append(String(localized: "Fan monitoring")) }
        if c.contains(.localButton) { parts.append(String(localized: "Stop button")) }
        return parts.joined(separator: ", ")
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}
