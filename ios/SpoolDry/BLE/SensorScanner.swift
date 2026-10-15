import CoreBluetooth
import Foundation
import Observation
import SpoolDryKit

/// A BTHome thermo-hygrometer heard nearby.
struct NearbySensor: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var reading: BTHomeReading
    var lastSeen: Date
}

/// Listens passively for BTHome v2 advertisements (service data UUID 0xFCD2) from off-the-shelf
/// Bluetooth thermo-hygrometers placed in filament storage boxes. No pairing, no connection, no cloud:
/// the sensors broadcast and SpoolDry reads the broadcast while the app is open.
///
/// Uses its own central so it never interferes with the dryer connection in `BLEManager`.
@MainActor
@Observable
final class SensorScanner: NSObject {
    static let demoSensorID = UUID(uuidString: "5D0F0000-DE30-4000-8000-0000000000B1")!

    private(set) var availability: BLEManager.BluetoothAvailability = .unknown
    private(set) var isScanning = false
    private(set) var nearby: [UUID: NearbySensor] = [:]

    @ObservationIgnored var onReading: ((UUID, BTHomeReading, Date) -> Void)?
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var demoTimer: Timer?
    @ObservationIgnored private var demoPhase: Double = 0

    var sortedNearby: [NearbySensor] {
        nearby.values.filter { $0.id != Self.demoSensorID }.sorted { $0.rssi > $1.rssi }
    }

    /// Starts listening until `stop()`; creating the central shows the Bluetooth permission prompt the first time.
    func start() {
        stopTask?.cancel()
        wantsScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else {
            beginScan()
        }
    }

    /// Listens for a short while (used when the app comes to the foreground) to refresh dry boxes.
    func scanBriefly(seconds: Double = 45) {
        guard !wantsScan else { return }
        start()
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        wantsScan = false
        central?.stopScan()
        isScanning = false
    }

    private func beginScan() {
        guard wantsScan, let central, central.state == .poweredOn, !central.isScanning else { return }
        // BTHome sensors send service *data* only, so the scan cannot be filtered by service UUID;
        // advertisements are filtered below. Foreground only.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    private func handle(id: UUID, name: String, rssi: Int, reading: BTHomeReading, at now: Date) {
        if let previous = nearby[id], previous.reading.packetID != nil, previous.reading.packetID == reading.packetID,
           now.timeIntervalSince(previous.lastSeen) < 60 {
            nearby[id]?.rssi = rssi
            return   // same packet repeated
        }
        nearby[id] = NearbySensor(id: id, name: name, rssi: rssi, reading: reading, lastSeen: now)
        if reading.hasHumidity { onReading?(id, reading, now) }
    }

    // MARK: Demo sensor (for trying the feature and for App Review without hardware)

    /// Simulates a BTHome sensor in a dry box: slow humidity drift with a short "lid opened" spike.
    func setDemoSensorActive(_ active: Bool) {
        if !active {
            demoTimer?.invalidate()
            demoTimer = nil
            nearby[Self.demoSensorID] = nil
            return
        }
        guard demoTimer == nil else { return }
        tickDemo()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickDemo() }
        }
    }

    private func tickDemo() {
        demoPhase += 1
        let reading = BTHomeReading(temperatureCelsius: Self.demoTemperature(phase: demoPhase),
                                    humidityPercent: Self.demoHumidity(phase: demoPhase),
                                    batteryPercent: 92, packetID: UInt8(Int(demoPhase) % 256))
        handle(id: Self.demoSensorID, name: String(localized: "Demo Sensor"), rssi: -50, reading: reading, at: Date())
    }

    /// Demo humidity: ~14-19 %RH with a spike to ~27 %RH every 90 ticks (lid opened, then recovering).
    static func demoHumidity(phase: Double) -> Double {
        let base = 16.5 + 2.5 * sin(phase / 12)
        let cycle = phase.truncatingRemainder(dividingBy: 90)
        let spike = cycle < 15 ? 11 * exp(-cycle / 5) : 0
        return ((base + spike) * 10).rounded() / 10
    }

    static func demoTemperature(phase: Double) -> Double {
        ((23.4 + 0.6 * sin(phase / 30)) * 10).rounded() / 10
    }

    /// 24 h of realistic history for a newly added demo box, so its chart is not empty.
    static func demoHistory(now: Date = Date()) -> [HumiditySample] {
        stride(from: 144, through: 1, by: -1).map { i in
            let p = Double(i) * 1.7
            let t = now.addingTimeInterval(-Double(i) * 600)
            return HumiditySample(t: t, h: demoHumidity(phase: p + 30), c: demoTemperature(phase: p))
        }
    }

    private static func availability(from state: CBManagerState) -> BLEManager.BluetoothAvailability {
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

extension SensorScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            availability = Self.availability(from: central.state)
            if central.state == .poweredOn { beginScan() } else { isScanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let payload = serviceData[CBUUID(string: BTHomeParser.serviceUUID)],
              let reading = BTHomeParser.parse(payload) else { return }
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let id = peripheral.identifier
        let peripheralName = peripheral.name
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            let name = advName ?? peripheralName ?? String(localized: "BTHome sensor")
            handle(id: id, name: name, rssi: rssi, reading: reading, at: Date())
        }
    }
}
