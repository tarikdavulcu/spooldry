import Foundation
import SpoolDryKit
import SwiftData

/// A filament storage box watched by a Bluetooth thermo-hygrometer (BTHome) or the demo sensor.
@Model
final class DryBox {
    @Attribute(.unique) var id: UUID
    var name: String
    /// CoreBluetooth identifier of the BTHome sensor; nil for a box without a sensor.
    var sensorID: UUID?
    var sensorName: String
    var isDemo: Bool
    /// Warn when the box humidity rises above this value (%RH).
    var humidityLimit: Double
    var createdAt: Date
    var sortIndex: Int
    var lastHumidity: Double?
    var lastTemperature: Double?
    var lastBattery: Int?
    var lastSeenAt: Date?
    /// Set while the box is above its limit, so the warning is sent once per crossing.
    var alertSentAt: Date?
    /// 10-minute samples for the last 14 days (JSON [HumiditySample]).
    var samplesData: Data?

    init(name: String, sensorID: UUID?, sensorName: String = "", isDemo: Bool = false, humidityLimit: Double = 20,
         sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sensorID = sensorID
        self.sensorName = sensorName
        self.isDemo = isDemo
        self.humidityLimit = humidityLimit
        self.createdAt = Date()
        self.sortIndex = sortIndex
    }

    var samples: [HumiditySample] {
        get { samplesData.flatMap { try? JSONDecoder().decode([HumiditySample].self, from: $0) } ?? [] }
        set { samplesData = try? JSONEncoder().encode(newValue) }
    }

    var isAboveLimit: Bool { (lastHumidity ?? 0) > humidityLimit }

    /// A reading is considered current for 30 minutes.
    func isFresh(now: Date = Date()) -> Bool {
        guard let lastSeenAt else { return false }
        return now.timeIntervalSince(lastSeenAt) < 30 * 60
    }

    func record(humidity: Double, temperature: Double?, battery: Int?, at date: Date = Date()) {
        lastHumidity = humidity
        if let temperature { lastTemperature = temperature }
        if let battery { lastBattery = battery }
        lastSeenAt = date
        var s = samples
        if let last = s.last, date.timeIntervalSince(last.t) < 600 {
            s[s.count - 1] = HumiditySample(t: last.t, h: max(last.h, humidity), c: temperature ?? last.c)
        } else {
            s.append(HumiditySample(t: date, h: humidity, c: temperature))
        }
        samples = StorageAdvisor.compact(s, now: date)
    }
}

/// One filament spool in the user's inventory.
@Model
final class Spool {
    @Attribute(.unique) var id: UUID
    var materialRaw: Int
    var brand: String
    var colorName: String
    var remainingGrams: Int?
    /// The DryBox the spool is stored in; nil means room air.
    var boxID: UUID?
    var lastDriedAt: Date?
    var notes: String
    var createdAt: Date

    init(material: MaterialCode, brand: String = "", colorName: String = "", remainingGrams: Int? = nil,
         boxID: UUID? = nil, lastDriedAt: Date? = nil, notes: String = "") {
        self.id = UUID()
        self.materialRaw = Int(material.rawValue)
        self.brand = brand
        self.colorName = colorName
        self.remainingGrams = remainingGrams
        self.boxID = boxID
        self.lastDriedAt = lastDriedAt
        self.notes = notes
        self.createdAt = Date()
    }

    var material: MaterialCode {
        get { MaterialCode(rawValue: UInt8(clamping: materialRaw)) ?? .custom }
        set { materialRaw = Int(newValue.rawValue) }
    }

    var title: String {
        let parts = [brand, material.shortName, colorName].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    var guidance: FilamentGuidance? { FilamentDatabase.guidance(for: material) }

    func condition(in box: DryBox?, now: Date = Date()) -> SpoolCondition {
        let sensitivity = guidance?.sensitivity ?? .high
        if let box, box.sensorID != nil || box.isDemo {
            return StorageAdvisor.conditionInBox(sensitivity: sensitivity, humidityTarget: StorageAdvisor.storageHumidityLimit(sensitivity),
                                                 lastDried: lastDriedAt, samples: box.samples, now: now)
        }
        return StorageAdvisor.conditionInOpenAir(sensitivity: sensitivity, lastDried: lastDriedAt, now: now)
    }
}
