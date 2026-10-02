import CoreBluetooth
import Foundation
import Observation
import SpoolDryKit

/// A peripheral seen while scanning during device setup.
struct DiscoveredDryer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
}

/// CoreBluetooth central for SpoolDry. Direct phone <-> ESP32 communication, no cloud.
///
/// - Uses the `bluetooth-central` background mode so status notifications keep Live Activities current.
/// - Saved dryers are reconnected with pending `connect` calls (iOS completes them when back in range).
/// - State restoration keeps connections across app termination by the system.
@MainActor
@Observable
final class BLEManager: NSObject {
    enum BluetoothAvailability: Equatable {
        case unknown, poweredOn, poweredOff, unauthorized, unsupported, resetting
    }

    private(set) var availability: BluetoothAvailability = .unknown
    private(set) var isScanning = false
    private(set) var discovered: [DiscoveredDryer] = []
    private(set) var links: [UUID: DeviceLink] = [:]

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var savedDeviceIDs: Set<UUID> = []
    @ObservationIgnored var onLinkCreated: ((DeviceLink) -> Void)?
    @ObservationIgnored var onConnected: ((DeviceLink) -> Void)?
    @ObservationIgnored var onDisconnected: ((DeviceLink) -> Void)?

    static let restoreIdentifier = "com.tarikdavulcu.spooldry.central"
    private let serviceUUID = CBUUID(string: SpoolDryProtocol.serviceUUID)
    private let disUUID = CBUUID(string: "180A")

    /// Creates the central lazily so the Bluetooth permission prompt appears only after the user chose to connect.
    func activate() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    var isActivated: Bool { central != nil }

    func link(for id: UUID) -> DeviceLink? { links[id] }

    // MARK: Saved devices

    func registerSavedDevices(_ devices: [(id: UUID, name: String)]) {
        for d in devices {
            savedDeviceIDs.insert(d.id)
            let link = ensureLink(id: d.id, name: d.name)
            link.name = d.name
        }
        reconnectSaved()
    }

    func reconnectSaved() {
        guard let central, central.state == .poweredOn else { return }
        let ids = Array(savedDeviceIDs.subtracting([DemoDevice.deviceID]))
        for p in central.retrievePeripherals(withIdentifiers: ids) where p.state == .disconnected {
            connect(peripheral: p)
        }
    }

    func forget(id: UUID) {
        savedDeviceIDs.remove(id)
        if let link = links[id] {
            link.demo?.stop()
            if let p = link.peripheral { central?.cancelPeripheralConnection(p) }
            link.failAllPending(.notConnected)
        }
        links[id] = nil
    }

    // MARK: Demo device

    func addDemoDevice(name: String) -> DeviceLink {
        let link = ensureLink(id: DemoDevice.deviceID, name: name, isDemo: true)
        if link.demo == nil {
            let demo = DemoDevice()
            demo.link = link
            link.demo = demo
            link.info = demo.info
            link.linkState = .connected
            demo.start()
            onConnected?(link)
        }
        return link
    }

    // MARK: Scanning

    func startScan() {
        activate()
        discovered.removeAll()
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    func connect(id: UUID) {
        guard let central else { return }
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        connect(peripheral: p)
    }

    func disconnect(id: UUID) {
        guard let link = links[id], let p = link.peripheral else { return }
        savedDeviceIDs.remove(id)
        central?.cancelPeripheralConnection(p)
    }

    func markSaved(id: UUID) { savedDeviceIDs.insert(id) }

    private func connect(peripheral p: CBPeripheral) {
        let link = ensureLink(id: p.identifier, name: p.name ?? "SpoolDry")
        link.peripheral = p
        p.delegate = self
        link.linkState = .connecting
        central?.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: false])
    }

    @discardableResult
    private func ensureLink(id: UUID, name: String, isDemo: Bool = false) -> DeviceLink {
        if let l = links[id] { return l }
        let l = DeviceLink(id: id, name: name, isDemo: isDemo)
        links[id] = l
        onLinkCreated?(l)
        return l
    }

    private func setupGATT(_ p: CBPeripheral) {
        p.discoverServices([serviceUUID, disUUID])
    }

    private static func availability(from state: CBManagerState) -> BluetoothAvailability {
        switch state {
        case .poweredOn: return .poweredOn
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported: return .unsupported
        case .resetting: return .resetting
        default: return .unknown
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            availability = Self.availability(from: central.state)
            if central.state == .poweredOn {
                reconnectSaved()
            } else {
                isScanning = false
                for link in links.values where !link.isDemo {
                    link.linkState = .disconnected
                    link.failAllPending(.notConnected)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
            for p in peripherals {
                let link = ensureLink(id: p.identifier, name: p.name ?? "SpoolDry")
                link.peripheral = p
                p.delegate = self
                savedDeviceIDs.insert(p.identifier)
                if p.state == .connected {
                    link.linkState = .connecting
                    setupGATT(p)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = advName ?? peripheral.name ?? "SpoolDry"
            let entry = DiscoveredDryer(id: peripheral.identifier, name: name, rssi: RSSI.intValue, lastSeen: Date())
            if let i = discovered.firstIndex(where: { $0.id == entry.id }) {
                discovered[i] = entry
            } else {
                discovered.append(entry)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard let link = links[peripheral.identifier] else { return }
            link.lastErrorMessage = nil
            setupGATT(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            guard let link = links[peripheral.identifier] else { return }
            link.linkState = .disconnected
            link.lastErrorMessage = error?.localizedDescription
            if savedDeviceIDs.contains(peripheral.identifier) { connect(peripheral: peripheral) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        MainActor.assumeIsolated {
            guard let link = links[peripheral.identifier] else { return }
            link.linkState = isReconnecting ? .connecting : .disconnected
            link.characteristics.removeAll()
            link.failAllPending(.notConnected)
            onDisconnected?(link)
            // The dryer keeps running its session autonomously. Re-arm a pending connection so iOS
            // reconnects as soon as the phone is back in range (also while the app is in background).
            if !isReconnecting, savedDeviceIDs.contains(peripheral.identifier) {
                connect(peripheral: peripheral)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for s in peripheral.services ?? [] where s.uuid == serviceUUID {
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard service.uuid == serviceUUID, let link = links[peripheral.identifier] else { return }
            for c in service.characteristics ?? [] { link.characteristics[c.uuid] = c }
            let found = link.characteristics
            func chr(_ c: SpoolDryCharacteristic) -> CBCharacteristic? { found[CBUUID(string: c.rawValue)] }
            guard let status = chr(.deviceStatus), let response = chr(.commandResponse), chr(.command) != nil else {
                link.lastErrorMessage = String(localized: "This device does not expose the SpoolDry service correctly.")
                return
            }
            if let info = chr(.deviceInfo) { peripheral.readValue(for: info) }
            if let session = chr(.dryingSession) { peripheral.readValue(for: session) }
            peripheral.setNotifyValue(true, for: response)
            peripheral.setNotifyValue(true, for: status)
            peripheral.readValue(for: status)
            link.linkState = .connected
            onConnected?(link)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let link = links[peripheral.identifier] else { return }
            if let error {
                Self.handleATTError(error, link: link)
                return
            }
            guard let value = characteristic.value else { return }
            link.handleValue(value, for: characteristic.uuid)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let error, let link = links[peripheral.identifier] else { return }
            Self.handleATTError(error, link: link)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let error, let link = links[peripheral.identifier] else { return }
            Self.handleATTError(error, link: link)
        }
    }

    private static func handleATTError(_ error: Error, link: DeviceLink) {
        if let att = error as? CBATTError,
           att.code == .insufficientEncryption || att.code == .insufficientAuthentication {
            // iOS shows the system pairing dialog; the dryer accepts new phones for 5 minutes after power-on.
            link.needsPairing = true
            link.lastErrorMessage = String(localized: "Pairing required. Accept the Bluetooth pairing request. New phones can pair within 5 minutes after the dryer is switched on.")
        } else {
            link.lastErrorMessage = error.localizedDescription
        }
    }
}
