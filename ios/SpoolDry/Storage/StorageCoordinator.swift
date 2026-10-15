import Foundation
import Observation
import SpoolDryKit
import SwiftData
import UserNotifications

/// Connects BTHome sensor readings to the user's dry boxes and spools.
@MainActor
@Observable
final class StorageCoordinator {
    let scanner = SensorScanner()
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var lastSave = Date.distantPast

    init(context: ModelContext) {
        self.context = context
        scanner.onReading = { [weak self] id, reading, date in
            self?.ingest(sensorID: id, reading: reading, at: date)
        }
    }

    // MARK: Queries

    func boxes() -> [DryBox] {
        let d = FetchDescriptor<DryBox>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)])
        return (try? context.fetch(d)) ?? []
    }

    func box(id: UUID?) -> DryBox? {
        guard let id else { return nil }
        return boxes().first { $0.id == id }
    }

    func spools() -> [Spool] {
        let d = FetchDescriptor<Spool>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(d)) ?? []
    }

    var hasSensorBoxes: Bool { boxes().contains { $0.sensorID != nil && !$0.isDemo } }

    // MARK: Lifecycle

    /// Called when the app becomes active: refresh real sensors briefly and keep the demo sensor running if used.
    func appBecameActive() {
        scanner.setDemoSensorActive(boxes().contains { $0.isDemo })
        if hasSensorBoxes { scanner.scanBriefly() }
    }

    // MARK: Boxes

    @discardableResult
    func addBox(name: String, sensor: NearbySensor?, humidityLimit: Double) -> DryBox {
        let box = DryBox(name: name, sensorID: sensor?.id, sensorName: sensor?.name ?? "", humidityLimit: humidityLimit,
                         sortIndex: boxes().count)
        if let r = sensor?.reading, let h = r.humidityPercent {
            box.record(humidity: h, temperature: r.temperatureCelsius, battery: r.batteryPercent)
        }
        context.insert(box)
        try? context.save()
        return box
    }

    @discardableResult
    func addDemoBox() -> DryBox {
        if let existing = boxes().first(where: { $0.isDemo }) { return existing }
        let box = DryBox(name: String(localized: "Demo Dry Box"), sensorID: SensorScanner.demoSensorID,
                         sensorName: String(localized: "Demo Sensor"), isDemo: true, humidityLimit: 20, sortIndex: boxes().count)
        let history = SensorScanner.demoHistory()
        box.samples = history
        if let last = history.last { box.record(humidity: last.h, temperature: last.c, battery: 92, at: last.t) }
        context.insert(box)
        // Two example spools so the condition estimates can be seen immediately.
        context.insert(Spool(material: .petg, brand: "Demo", colorName: String(localized: "Black"), remainingGrams: 820,
                             boxID: box.id, lastDriedAt: Date().addingTimeInterval(-3 * 86400)))
        context.insert(Spool(material: .pa, brand: "Demo", colorName: String(localized: "Natural"), remainingGrams: 450,
                             boxID: box.id, lastDriedAt: Date().addingTimeInterval(-9 * 86400)))
        try? context.save()
        scanner.setDemoSensorActive(true)
        return box
    }

    func delete(_ box: DryBox) {
        for s in spools() where s.boxID == box.id { s.boxID = nil }
        let wasDemo = box.isDemo
        context.delete(box)
        try? context.save()
        if wasDemo { scanner.setDemoSensorActive(false) }
    }

    // MARK: Spools

    func markDried(_ ids: [UUID], at date: Date = Date()) {
        guard !ids.isEmpty else { return }
        for s in spools() where ids.contains(s.id) { s.lastDriedAt = date }
        try? context.save()
    }

    // MARK: Readings

    private func ingest(sensorID: UUID, reading: BTHomeReading, at date: Date) {
        guard let h = reading.humidityPercent else { return }
        for box in boxes() where box.sensorID == sensorID {
            let wasAbove = box.isAboveLimit
            box.record(humidity: h, temperature: reading.temperatureCelsius, battery: reading.batteryPercent, at: date)
            if box.isAboveLimit && !wasAbove && box.alertSentAt == nil && !box.isDemo {
                box.alertSentAt = date
                notifyHumid(box)
            } else if !box.isAboveLimit {
                box.alertSentAt = nil
            }
        }
        if date.timeIntervalSince(lastSave) > 30 {
            lastSave = date
            try? context.save()
        }
    }

    private func notifyHumid(_ box: DryBox) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Dry box too humid")
        let humidity = SpoolDryFormat.humidity(box.lastHumidity)
        let limit = SpoolDryFormat.humidity(box.humidityLimit)
        content.body = String(localized: "\(box.name) is at \(humidity) (limit \(limit)). Check the desiccant and the lid seal.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "box-\(box.id.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
