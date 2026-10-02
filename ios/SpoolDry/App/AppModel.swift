import Foundation
import Observation
import SpoolDryKit
import SwiftData

enum AppTab: Hashable {
    case dashboard, profiles, history, device, settings
}

/// Root application state. Owns the BLE stack, StoreKit and the session coordinator.
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let ble = BLEManager()
    let store: StoreManager
    let sessions: SessionCoordinator

    var selectedTab: AppTab = .dashboard
    var showPaywall = false
    var showDeviceSetup = false
    /// The dryer shown on the dashboard (persisted).
    var activeDeviceID: UUID? {
        get { storedActiveDeviceID }
        set {
            storedActiveDeviceID = newValue
            UserDefaults.standard.set(newValue?.uuidString, forKey: SettingsKeys.activeDevice)
        }
    }
    private var storedActiveDeviceID: UUID?

    @ObservationIgnored private var bootstrapped = false

    init(inMemory: Bool = false) {
        let container = PersistenceController.makeContainer(inMemory: inMemory)
        let store = StoreManager()
        self.container = container
        self.store = store
        self.sessions = SessionCoordinator(context: container.mainContext, store: store)
        self.storedActiveDeviceID = UserDefaults.standard.string(forKey: SettingsKeys.activeDevice).flatMap(UUID.init(uuidString:))
        sessions.activeDeviceIDProvider = { [weak self] in self?.activeLink?.id }
        ble.onLinkCreated = { [weak self] link in self?.wire(link) }
        ble.onConnected = { [weak self] link in self?.didConnect(link) }
        ble.onDisconnected = { [weak self] link in self?.sessions.handleLinkChange(link) }
    }

    var context: ModelContext { container.mainContext }

    /// The dryer shown on the dashboard.
    var activeLink: DeviceLink? {
        if let id = activeDeviceID, let link = ble.links[id] { return link }
        return sortedLinks.first
    }

    var sortedLinks: [DeviceLink] {
        let order = Dictionary(uniqueKeysWithValues: savedDevices().map { ($0.peripheralID, $0.sortIndex) })
        return ble.links.values.sorted { (order[$0.id] ?? 0, $0.name) < (order[$1.id] ?? 0, $1.name) }
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        let devices = savedDevices()
        if devices.contains(where: { !$0.isDemo }) { ble.activate() }
        for d in devices where d.isDemo { _ = ble.addDemoDevice(name: d.name) }
        ble.registerSavedDevices(devices.filter { !$0.isDemo }.map { (id: $0.peripheralID, name: $0.name) })
        sessions.restoreInProgressSessions()
        let retention = (UserDefaults.standard.object(forKey: SettingsKeys.retentionDays) as? Int) ?? 90
        PersistenceController.pruneSamples(in: context, olderThanDays: retention)
        await store.start()
    }

    // MARK: Devices

    func savedDevices() -> [SavedDevice] {
        let descriptor = FetchDescriptor<SavedDevice>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.addedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func savedDevice(id: UUID) -> SavedDevice? { savedDevices().first { $0.peripheralID == id } }

    /// Free tier: one dryer. Lifetime: unlimited dryers.
    var canAddAnotherDevice: Bool {
        store.hasLifetime || savedDevices().filter { !$0.isDemo }.isEmpty
    }

    func save(link: DeviceLink, advertisedName: String) {
        if let existing = savedDevice(id: link.id) {
            existing.lastSeenAt = Date()
        } else {
            let realCount = savedDevices().filter { !$0.isDemo }.count
            let name = realCount == 0 ? advertisedName : "\(advertisedName) #\(realCount + 1)"
            let d = SavedDevice(peripheralID: link.id, name: name, advertisedName: advertisedName,
                                isDemo: link.isDemo, sortIndex: savedDevices().count)
            if let info = link.info { apply(info, to: d) }
            context.insert(d)
            link.name = name
        }
        ble.markSaved(id: link.id)
        try? context.save()
        activeDeviceID = link.id
    }

    func addDemoDevice() {
        let link = ble.addDemoDevice(name: String(localized: "Demo Dryer"))
        save(link: link, advertisedName: String(localized: "Demo Dryer"))
    }

    func forget(id: UUID) {
        ble.forget(id: id)
        if let d = savedDevice(id: id) { context.delete(d) }
        try? context.save()
        if activeDeviceID == id { activeDeviceID = sortedLinks.first?.id }
    }

    func rename(link: DeviceLink, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // The advertised BLE name is limited to 20 bytes; the in-app name can be longer.
        if !link.isDemo, link.isReady {
            var bleName = ""
            for ch in trimmed {
                guard (bleName + String(ch)).utf8.count <= 20 else { break }
                bleName.append(ch)
            }
            try await link.send(.setDeviceName(bleName))
        }
        link.name = trimmed
        savedDevice(id: link.id)?.name = trimmed
        try? context.save()
    }

    // MARK: Wiring

    private func wire(_ link: DeviceLink) {
        link.onStatus = { [weak self] link, status in
            self?.sessions.handleStatus(status, from: link)
        }
        link.onInfo = { [weak self] link, info in
            guard let self, let d = self.savedDevice(id: link.id) else { return }
            self.apply(info, to: d)
            try? self.context.save()
        }
    }

    private func didConnect(_ link: DeviceLink) {
        if let d = savedDevice(id: link.id) {
            d.lastSeenAt = Date()
            link.name = d.name
            try? context.save()
        }
    }

    private func apply(_ info: DeviceInfo, to d: SavedDevice) {
        d.deviceIdHex = info.deviceId.hexString
        d.firmwareVersion = info.firmwareVersion
        d.protocolVersion = Int(info.protocolVersion)
        d.hardwareRevision = Int(info.hardwareRevision)
        d.maxTargetCelsius = info.maxTargetCelsius
        d.lastSeenAt = Date()
    }
}
