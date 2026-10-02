import Foundation

/// Minimal session data needed to compute statistics (decoupled from SwiftData).
public struct SessionStatInput: Equatable, Sendable {
    public var material: MaterialCode
    public var filamentName: String
    public var startedAt: Date
    public var dryingSeconds: TimeInterval
    public var outcome: SessionOutcome
    public var startHumidity: Double?
    public var endHumidity: Double?

    public init(material: MaterialCode, filamentName: String, startedAt: Date, dryingSeconds: TimeInterval,
                outcome: SessionOutcome, startHumidity: Double?, endHumidity: Double?) {
        self.material = material
        self.filamentName = filamentName
        self.startedAt = startedAt
        self.dryingSeconds = dryingSeconds
        self.outcome = outcome
        self.startHumidity = startHumidity
        self.endHumidity = endHumidity
    }
}

public struct DryingStatistics: Equatable, Sendable {
    public var totalSessions: Int
    public var completedSessions: Int
    public var totalDryingHours: Double
    /// Average (start - end) RH in percentage points over sessions that have both readings.
    public var averageHumidityReduction: Double?
    public var mostUsedMaterial: MaterialCode?
    public var lastSessionDate: Date?
    public var sessionsPerMaterial: [(material: MaterialCode, count: Int)]

    public static func == (a: Self, b: Self) -> Bool {
        a.totalSessions == b.totalSessions && a.completedSessions == b.completedSessions &&
            a.totalDryingHours == b.totalDryingHours && a.averageHumidityReduction == b.averageHumidityReduction &&
            a.mostUsedMaterial == b.mostUsedMaterial && a.lastSessionDate == b.lastSessionDate &&
            a.sessionsPerMaterial.map(\.material) == b.sessionsPerMaterial.map(\.material) &&
            a.sessionsPerMaterial.map(\.count) == b.sessionsPerMaterial.map(\.count)
    }

    public static func compute(_ sessions: [SessionStatInput]) -> DryingStatistics {
        let finished = sessions.filter { $0.outcome != .inProgress }
        let total = finished.count
        let completed = finished.filter { $0.outcome == .completed }.count
        let hours = finished.reduce(0) { $0 + $1.dryingSeconds } / 3600.0
        let reductions = finished.compactMap { s -> Double? in
            guard let a = s.startHumidity, let b = s.endHumidity else { return nil }
            return a - b
        }
        let avgReduction = reductions.isEmpty ? nil : reductions.reduce(0, +) / Double(reductions.count)
        var counts: [MaterialCode: Int] = [:]
        for s in finished { counts[s.material, default: 0] += 1 }
        let perMaterial = counts.map { (material: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.material.rawValue < $1.material.rawValue }
        return DryingStatistics(totalSessions: total, completedSessions: completed, totalDryingHours: hours,
                                averageHumidityReduction: avgReduction, mostUsedMaterial: perMaterial.first?.material,
                                lastSessionDate: finished.map(\.startedAt).max(), sessionsPerMaterial: perMaterial)
    }
}
