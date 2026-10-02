import SpoolDryKit
import SwiftUI
import UIKit

/// First-run BLE setup:
/// 1 turn on dryer → 2 Bluetooth → 3 scan → 4 device appears → 5 tap → 6 connect →
/// 7 read firmware/device info → 8 save → 9 dashboard.
struct DeviceSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var connectingID: UUID?
    @State private var connectedLink: DeviceLink?
    @State private var timeoutMessage: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetupStep(number: 1, title: "Switch on your SpoolDry dryer", done: true)
                    SetupStep(number: 2, title: "Bluetooth is on", done: model.ble.availability == .poweredOn)
                    SetupStep(number: 3, title: "Searching for dryers nearby", done: !model.ble.discovered.isEmpty,
                              busy: model.ble.isScanning && model.ble.discovered.isEmpty)
                    SetupStep(number: 4, title: "Connect and read device information", done: connectedLink?.info != nil,
                              busy: connectingID != nil && connectedLink?.info == nil)
                }

                bluetoothNotice

                if !model.ble.discovered.isEmpty && connectedLink == nil {
                    Section("Dryers found") {
                        ForEach(model.ble.discovered) { d in
                            Button {
                                connect(d)
                            } label: {
                                HStack {
                                    Image(systemName: "cpu").foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading) {
                                        Text(d.name).font(.headline)
                                        Text(signalText(d.rssi)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if connectingID == d.id { ProgressView() }
                                }
                            }
                            .disabled(connectingID != nil)
                        }
                    }
                }

                if let link = connectedLink, let info = link.info {
                    Section("Connected") {
                        InfoRow(title: "Name", value: link.name)
                        InfoRow(title: "Firmware", value: info.firmwareVersion)
                        InfoRow(title: "BLE protocol", value: "v\(info.protocolVersion)")
                        InfoRow(title: "Maximum temperature", value: String(format: "%.0f °C", info.maxTargetCelsius))
                        if !info.isProtocolSupported {
                            Text("This firmware uses a newer protocol. Update SpoolDry from the App Store.")
                                .foregroundStyle(Theme.danger)
                        }
                        Button {
                            model.save(link: link, advertisedName: link.name)
                            saved = true
                            model.ble.stopScan()
                            dismiss()
                        } label: {
                            Text("Save and Open Dashboard").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowBackground(Color.clear)
                        .disabled(!info.isProtocolSupported)
                    }
                }

                if let timeoutMessage {
                    Section { Text(timeoutMessage).foregroundStyle(.orange) }
                }

                Section {
                    Text("Pairing: the first command asks iOS to pair with the dryer. New phones can pair within 5 minutes after the dryer is switched on (or after holding its BOOT button for 10 seconds).")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("No hardware yet? Use the Demo Dryer") {
                        model.addDemoDevice()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Set Up Dryer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.ble.stopScan()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Scan Again") { model.ble.startScan() }.disabled(model.ble.availability != .poweredOn)
                }
            }
            .onAppear { model.ble.startScan() }
            .onChange(of: model.ble.availability) { _, new in
                if new == .poweredOn && !model.ble.isScanning && connectedLink == nil { model.ble.startScan() }
            }
            .onDisappear {
                model.ble.stopScan()
                // A dryer that was connected but not saved is released again.
                if let link = connectedLink, !saved, model.savedDevice(id: link.id) == nil { model.ble.forget(id: link.id) }
                if let id = connectingID, model.savedDevice(id: id) == nil { model.ble.forget(id: id) }
            }
        }
    }

    @ViewBuilder
    private var bluetoothNotice: some View {
        switch model.ble.availability {
        case .poweredOff:
            Section { Label("Turn on Bluetooth in Control Center or Settings.", systemImage: "bolt.horizontal.circle") }
        case .unauthorized:
            Section {
                Label("SpoolDry needs Bluetooth permission to talk to your dryer. Enable it in Settings > SpoolDry.",
                      systemImage: "hand.raised")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        case .unsupported:
            Section { Label("This device does not support Bluetooth Low Energy.", systemImage: "xmark.octagon") }
        default:
            EmptyView()
        }
    }

    private func signalText(_ rssi: Int) -> String {
        if rssi >= -60 { return String(localized: "Signal: excellent") }
        if rssi >= -75 { return String(localized: "Signal: good") }
        return String(localized: "Signal: weak. Move closer.")
    }

    private func connect(_ d: DiscoveredDryer) {
        connectingID = d.id
        timeoutMessage = nil
        model.ble.stopScan()
        model.ble.connect(id: d.id)
        Task { @MainActor in
            // Wait for GATT discovery + Device Info read (max 15 s).
            for _ in 0..<60 {
                if let link = model.ble.link(for: d.id), link.linkState == .connected, link.info != nil {
                    link.name = d.name
                    connectedLink = link
                    connectingID = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            connectingID = nil
            timeoutMessage = String(localized: "Could not read the dryer. Make sure it runs SpoolDry firmware and try again.")
            model.ble.startScan()
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let title: LocalizedStringKey
    let done: Bool
    var busy: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Theme.success.opacity(0.2) : Color.secondary.opacity(0.15))
                if busy {
                    ProgressView()
                } else if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.success)
                } else {
                    Text("\(number)").font(.caption.weight(.bold))
                }
            }
            .frame(width: 30, height: 30)
            Text(title)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? Text("Done") : Text("Pending"))
    }
}
