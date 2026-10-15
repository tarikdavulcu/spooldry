import Foundation

/// One humidity reading from a dry-box sensor.
public struct HumiditySample: Codable, Equatable, Sendable {
    public var t: Date
    public var h: Double
    public var c: Double?

    public init(t: Date, h: Double, c: Double? = nil) {
        self.t = t
        self.h = h
        self.c = c
    }
}

/// How dry a spool is likely to be, estimated from where it was stored since it was last dried.
public enum SpoolCondition: String, Codable, Sendable, CaseIterable {
    /// Stored within the material's humidity target since the last drying.
    case dry
    /// Some exposure; fine for most prints, dry before critical parts.
    case watch
    /// Exposure is long enough that drying is recommended before printing.
    case needsDrying
    /// No drying date recorded.
    case unknown

    public var localizationKey: String { "spool.condition.\(rawValue)" }
}

/// Estimates spool condition. These are conservative app heuristics based on each material's typical
/// moisture sensitivity, not manufacturer specifications; the UI says so.
public enum StorageAdvisor {
    /// Readings further apart than this are not bridged (the sensor or the phone was away).
    public static let maxGap: TimeInterval = 2 * 3600

    /// Hours above `limit` %RH a material tolerates in a box before drying is recommended.
    public static func toleratedHoursAboveLimit(_ s: HumiditySensitivity) -> Double {
        switch s {
        case .veryHigh: return 6
        case .high: return 12
        case .moderate: return 48
        case .low: return 168
        }
    }

    /// Box humidity (%RH) up to which a material is considered well stored.
    public static func storageHumidityLimit(_ s: HumiditySensitivity) -> Double {
        switch s {
        case .veryHigh: return 15
        case .high: return 20
        case .moderate: return 30
        case .low: return 40
        }
    }

    /// Days in open room air after drying before re-drying is recommended.
    public static func openAirDays(_ s: HumiditySensitivity) -> Double {
        switch s {
        case .veryHigh: return 1
        case .high: return 2
        case .moderate: return 7
        case .low: return 14
        }
    }

    /// Total hours the box humidity spent above `limit` between `since` and `now`.
    /// Each sample holds until the next one (or `now`), capped at `maxGap`.
    public static func hoursAbove(limit: Double, samples: [HumiditySample], since: Date, now: Date = Date()) -> Double {
        let sorted = samples.sorted { $0.t < $1.t }
        var seconds: TimeInterval = 0
        for (idx, s) in sorted.enumerated() where s.h > limit {
            let next = idx + 1 < sorted.count ? sorted[idx + 1].t : now
            let start = max(s.t, since)
            let end = min(next, s.t.addingTimeInterval(maxGap), now)
            if end > start { seconds += end.timeIntervalSince(start) }
        }
        return seconds / 3600
    }

    /// Condition of a spool kept in a monitored dry box.
    public static func conditionInBox(sensitivity: HumiditySensitivity, humidityTarget: Double,
                                      lastDried: Date?, samples: [HumiditySample], now: Date = Date()) -> SpoolCondition {
        guard let lastDried else { return .unknown }
        let hours = hoursAbove(limit: humidityTarget, samples: samples, since: lastDried, now: now)
        let tolerated = toleratedHoursAboveLimit(sensitivity)
        if hours >= tolerated { return .needsDrying }
        if hours >= tolerated * 0.25 { return .watch }
        return .dry
    }

    /// Condition of a spool stored in room air (no monitored box).
    public static func conditionInOpenAir(sensitivity: HumiditySensitivity, lastDried: Date?, now: Date = Date()) -> SpoolCondition {
        guard let lastDried else { return .unknown }
        let days = now.timeIntervalSince(lastDried) / 86400
        let limit = openAirDays(sensitivity)
        if days >= limit { return .needsDrying }
        if days >= limit * 0.5 { return .watch }
        return .dry
    }

    /// Keeps one sample per `interval` (the latest in each bucket) and drops samples older than `keep`.
    public static func compact(_ samples: [HumiditySample], interval: TimeInterval = 600, keep: TimeInterval = 14 * 86400,
                               now: Date = Date()) -> [HumiditySample] {
        let cutoff = now.addingTimeInterval(-keep)
        var buckets: [Int: HumiditySample] = [:]
        for s in samples where s.t >= cutoff {
            let key = Int(s.t.timeIntervalSince1970 / interval)
            if let existing = buckets[key], existing.t > s.t { continue }
            buckets[key] = s
        }
        return buckets.values.sorted { $0.t < $1.t }
    }
}
