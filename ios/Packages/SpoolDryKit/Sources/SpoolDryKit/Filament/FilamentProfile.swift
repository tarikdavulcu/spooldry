import Foundation

/// A drying profile. Built-in profiles are derived from `FilamentDatabase` (typical starting guidance);
/// custom profiles are created by the user and stored on device.
public struct FilamentProfile: Identifiable, Hashable, Codable, Sendable {
    public enum Source: Hashable, Codable, Sendable {
        /// Typical starting guidance synthesised from manufacturer references.
        case builtInGuidance
        /// Entered by the user (optionally citing a data sheet URL).
        case user(reference: String?)
    }

    public var id: UUID
    public var brand: String
    public var material: MaterialCode
    public var name: String
    /// Drying temperature (°C).
    public var temperature: Double
    /// Drying duration (seconds).
    public var duration: TimeInterval
    /// Target chamber relative humidity (%).
    public var humidityTarget: Double
    public var notes: String
    public var source: Source
    public var lastVerified: Date?

    public init(id: UUID = UUID(), brand: String, material: MaterialCode, name: String, temperature: Double,
                duration: TimeInterval, humidityTarget: Double, notes: String = "", source: Source,
                lastVerified: Date? = nil) {
        self.id = id
        self.brand = brand
        self.material = material
        self.name = name
        self.temperature = temperature
        self.duration = duration
        self.humidityTarget = humidityTarget
        self.notes = notes
        self.source = source
        self.lastVerified = lastVerified
    }

    public var isBuiltIn: Bool { source == .builtInGuidance }

    /// Built-in profile for a material (deterministic ID so selections persist).
    public static func builtIn(_ g: FilamentGuidance) -> FilamentProfile {
        FilamentProfile(id: deterministicID(for: g.material), brand: "", material: g.material, name: g.displayName,
                        temperature: g.suggestedCelsius, duration: g.suggestedHours * 3600,
                        humidityTarget: g.humidityTargetPercent, notes: "", source: .builtInGuidance,
                        lastVerified: FilamentDatabase.lastVerified)
    }

    public static var builtIns: [FilamentProfile] { FilamentDatabase.all.map(builtIn) }

    static func deterministicID(for m: MaterialCode) -> UUID {
        UUID(uuidString: String(format: "5D0F0000-0000-4000-8000-%012X", Int(m.rawValue))) ?? UUID()
    }

    public enum ValidationIssue: Equatable, Sendable {
        case emptyName
        case temperatureBelowMinimum(Double)
        case temperatureAboveDeviceMax(Double)
        case durationTooShort
        case durationTooLong
        case humidityTargetOutOfRange
    }

    /// Validates against protocol and hardware limits. `deviceMax` comes from the connected device's Device Info.
    public func validate(deviceMaxCelsius: Double = FilamentDatabase.deviceMaxCelsius) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyName) }
        if temperature < FilamentDatabase.deviceMinCelsius { issues.append(.temperatureBelowMinimum(FilamentDatabase.deviceMinCelsius)) }
        if temperature > deviceMaxCelsius { issues.append(.temperatureAboveDeviceMax(deviceMaxCelsius)) }
        if duration < TimeInterval(SpoolDryProtocol.minDurationSec) { issues.append(.durationTooShort) }
        if duration > TimeInterval(SpoolDryProtocol.maxDurationSec) { issues.append(.durationTooLong) }
        if !(1...60).contains(humidityTarget) { issues.append(.humidityTargetOutOfRange) }
        return issues
    }
}

/// Everything needed to start a session on a device.
public struct DryingPlan: Equatable, Sendable, Codable {
    public var material: MaterialCode
    public var filamentName: String
    public var brand: String
    public var profileID: UUID?
    public var targetCelsius: Double
    public var durationSeconds: UInt32
    public var humidityTargetPercent: Double
    public var fanMode: FanMode

    public init(material: MaterialCode, filamentName: String, brand: String = "", profileID: UUID? = nil,
                targetCelsius: Double, durationSeconds: UInt32, humidityTargetPercent: Double, fanMode: FanMode = .auto) {
        self.material = material
        self.filamentName = filamentName
        self.brand = brand
        self.profileID = profileID
        self.targetCelsius = targetCelsius
        self.durationSeconds = durationSeconds
        self.humidityTargetPercent = humidityTargetPercent
        self.fanMode = fanMode
    }

    public init(profile: FilamentProfile, deviceMaxCelsius: Double = FilamentDatabase.deviceMaxCelsius) {
        let clampedTemp = min(max(profile.temperature, FilamentDatabase.deviceMinCelsius), deviceMaxCelsius)
        let clampedDuration = min(max(profile.duration, TimeInterval(SpoolDryProtocol.minDurationSec)),
                                  TimeInterval(SpoolDryProtocol.maxDurationSec))
        self.init(material: profile.material, filamentName: profile.name, brand: profile.brand, profileID: profile.id,
                  targetCelsius: clampedTemp, durationSeconds: UInt32(clampedDuration),
                  humidityTargetPercent: profile.humidityTarget)
    }

    public var command: DeviceCommand {
        .startSession(material: material, targetCelsius: targetCelsius, durationSeconds: durationSeconds, now: Date(), fanMode: fanMode)
    }

    /// Short label for Live Activities and widgets, e.g. "PA-CF" or "Polymaker PC".
    public var compactLabel: String {
        let n = filamentName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? material.shortName : n
    }
}
