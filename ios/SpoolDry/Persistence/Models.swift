import Foundation
import SpoolDryKit
import SwiftData

/// A dryer the user has set up. Multiple dryers are supported ("SpoolDry #1", "SpoolDry #2", ...).
@Model
final class SavedDevice {
    @Attribute(.unique) var peripheralID: UUID
    var name: String
    var advertisedName: String
    var deviceIdHex: String
    var firmwareVersion: String
    var protocolVersion: Int
    var hardwareRevision: Int
    var maxTargetCelsius: Double
    var isDemo: Bool
    var addedAt: Date
    var lastSeenAt: Date?
    var sortIndex: Int

    init(peripheralID: UUID, name: String, advertisedName: String, deviceIdHex: String = "", firmwareVersion: String = "",
         protocolVersion: Int = 1, hardwareRevision: Int = 1, maxTargetCelsius: Double = 70, isDemo: Bool = false,
         sortIndex: Int = 0) {
        self.peripheralID = peripheralID
        self.name = name
        self.advertisedName = advertisedName
        self.deviceIdHex = deviceIdHex
        self.firmwareVersion = firmwareVersion
        self.protocolVersion = protocolVersion
        self.hardwareRevision = hardwareRevision
        self.maxTargetCelsius = maxTargetCelsius
        self.isDemo = isDemo
        self.addedAt = Date()
        self.sortIndex = sortIndex
    }
}

/// One drying session in History. Raw sensor data is NOT stored indefinitely: only a 5-minute
/// downsampled chart series, which is pruned after the retention period (summaries are kept).
@Model
final class DryingSessionRecord {
    @Attribute(.unique) var id: UUID
    var deviceSessionId: Int
    var devicePeripheralID: UUID
    var deviceName: String
    var isDemo: Bool
    var materialRaw: Int
    var filamentName: String
    var brand: String
    var profileID: UUID?
    var targetCelsius: Double
    var durationSeconds: Int
    var humidityTargetPercent: Double
    var startedAt: Date
    var dryingStartedAt: Date?
    var endedAt: Date?
    var elapsedDryingSeconds: Int
    var outcomeRaw: String
    var errorCodeRaw: Int
    var startHumidity: Double?
    var endHumidity: Double?
    var minHumidity: Double?
    var averageTemperature: Double?
    var maxTemperature: Double?
    var samplesData: Data?

    init(plan: DryingPlan, deviceSessionId: UInt32, deviceID: UUID, deviceName: String, isDemo: Bool, startedAt: Date) {
        self.id = UUID()
        self.deviceSessionId = Int(deviceSessionId)
        self.devicePeripheralID = deviceID
        self.deviceName = deviceName
        self.isDemo = isDemo
        self.materialRaw = Int(plan.material.rawValue)
        self.filamentName = plan.filamentName
        self.brand = plan.brand
        self.profileID = plan.profileID
        self.targetCelsius = plan.targetCelsius
        self.durationSeconds = Int(plan.durationSeconds)
        self.humidityTargetPercent = plan.humidityTargetPercent
        self.startedAt = startedAt
        self.elapsedDryingSeconds = 0
        self.outcomeRaw = SessionOutcome.inProgress.rawValue
        self.errorCodeRaw = 0
    }

    var material: MaterialCode { MaterialCode(rawValue: UInt8(clamping: materialRaw)) ?? .custom }
    var outcome: SessionOutcome { SessionOutcome(rawValue: outcomeRaw) ?? .inProgress }
    var errorCode: DeviceErrorCode { DeviceErrorCode(rawValue: UInt8(clamping: errorCodeRaw)) ?? .none }
    var samples: [SessionSample] {
        guard let samplesData else { return [] }
        return (try? JSONDecoder().decode([SessionSample].self, from: samplesData)) ?? []
    }
    var displayName: String { filamentName.isEmpty ? material.shortName : filamentName }

    func apply(_ s: SessionSummary) {
        dryingStartedAt = s.dryingStartedAt
        endedAt = s.endedAt
        elapsedDryingSeconds = Int(s.elapsedDryingSeconds)
        outcomeRaw = s.outcome.rawValue
        errorCodeRaw = Int(s.errorCode.rawValue)
        startHumidity = s.startHumidity
        endHumidity = s.endHumidity
        minHumidity = s.minHumidity
        averageTemperature = s.averageDryingTemperature
        maxTemperature = s.maxTemperature
        if !s.samples.isEmpty { samplesData = try? JSONEncoder().encode(s.samples) }
    }

    var statInput: SessionStatInput {
        SessionStatInput(material: material, filamentName: displayName, startedAt: startedAt,
                         dryingSeconds: TimeInterval(elapsedDryingSeconds), outcome: outcome,
                         startHumidity: startHumidity, endHumidity: endHumidity)
    }
}

/// User-created filament profile (built-in guidance lives in SpoolDryKit and is not persisted).
@Model
final class CustomFilamentProfile {
    @Attribute(.unique) var id: UUID
    var brand: String
    var materialRaw: Int
    var name: String
    var temperatureCelsius: Double
    var durationSeconds: Double
    var humidityTarget: Double
    var notes: String
    var sourceReference: String
    var lastVerified: Date?
    var createdAt: Date

    init(from p: FilamentProfile) {
        id = p.id
        brand = p.brand
        materialRaw = Int(p.material.rawValue)
        name = p.name
        temperatureCelsius = p.temperature
        durationSeconds = p.duration
        humidityTarget = p.humidityTarget
        notes = p.notes
        if case let .user(reference) = p.source { sourceReference = reference ?? "" } else { sourceReference = "" }
        lastVerified = p.lastVerified
        createdAt = Date()
    }

    func update(from p: FilamentProfile) {
        brand = p.brand
        materialRaw = Int(p.material.rawValue)
        name = p.name
        temperatureCelsius = p.temperature
        durationSeconds = p.duration
        humidityTarget = p.humidityTarget
        notes = p.notes
        if case let .user(reference) = p.source { sourceReference = reference ?? "" }
        lastVerified = p.lastVerified
    }

    var profile: FilamentProfile {
        FilamentProfile(id: id, brand: brand, material: MaterialCode(rawValue: UInt8(clamping: materialRaw)) ?? .custom,
                        name: name, temperature: temperatureCelsius, duration: durationSeconds, humidityTarget: humidityTarget,
                        notes: notes, source: .user(reference: sourceReference.isEmpty ? nil : sourceReference),
                        lastVerified: lastVerified)
    }
}

enum PersistenceController {
    static let schema = Schema([SavedDevice.self, DryingSessionRecord.self, CustomFilamentProfile.self])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A corrupt store must not brick the app; fall back to memory and surface it in Settings.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }

    /// Keeps summaries forever but drops chart samples older than the retention window.
    @MainActor
    static func pruneSamples(in context: ModelContext, olderThanDays days: Int = 90) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let descriptor = FetchDescriptor<DryingSessionRecord>(predicate: #Predicate { $0.startedAt < cutoff })
        guard let old = try? context.fetch(descriptor) else { return }
        for r in old where r.samplesData != nil { r.samplesData = nil }
        try? context.save()
    }
}
