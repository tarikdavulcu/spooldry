import Foundation

/// History outcome of a drying session.
public enum SessionOutcome: String, Codable, Sendable, CaseIterable {
    case inProgress
    case completed
    case stopped
    case failed
    case overTemperature
    case disconnected

    public var localizationKey: String { "outcome.\(rawValue)" }
}

/// Compact sample kept for charts (5-minute resolution, capped).
public struct SessionSample: Codable, Equatable, Sendable {
    public var t: TimeInterval   // seconds since session start
    public var c: Double?        // chamber °C
    public var h: Double?        // RH %
    public init(t: TimeInterval, c: Double?, h: Double?) { self.t = t; self.c = c; self.h = h }
}

/// Value-type summary of a tracked session. The app maps it onto its SwiftData record.
public struct SessionSummary: Equatable, Sendable {
    public var deviceSessionId: UInt32
    public var startedAt: Date
    public var dryingStartedAt: Date?
    public var endedAt: Date?
    public var outcome: SessionOutcome
    public var errorCode: DeviceErrorCode
    public var elapsedDryingSeconds: UInt32
    public var startHumidity: Double?
    public var endHumidity: Double?
    public var minHumidity: Double?
    public var averageDryingTemperature: Double?
    public var maxTemperature: Double?
    public var samples: [SessionSample]
    public var lastState: DeviceState

    public var humidityReduction: Double? {
        guard let s = startHumidity, let e = endHumidity else { return nil }
        return s - e
    }
}

/// Follows Device Status updates for ONE session (identified by the device session ID returned in the
/// START_SESSION ACK) and derives the history record. Pure logic: deterministic and unit-tested.
public struct SessionTracker: Equatable, Sendable {
    public static let sampleInterval: TimeInterval = 300
    public static let maxSamples = 600  // 50 h at 5-minute resolution

    public private(set) var summary: SessionSummary
    private var tempSum: Double = 0
    private var tempCount: Int = 0
    private var lastSampleAt: Date?
    public let durationSeconds: UInt32

    public init(deviceSessionId: UInt32, startedAt: Date, durationSeconds: UInt32) {
        self.durationSeconds = durationSeconds
        summary = SessionSummary(deviceSessionId: deviceSessionId, startedAt: startedAt, dryingStartedAt: nil, endedAt: nil,
                                 outcome: .inProgress, errorCode: .none, elapsedDryingSeconds: 0, startHumidity: nil,
                                 endHumidity: nil, minHumidity: nil, averageDryingTemperature: nil, maxTemperature: nil,
                                 samples: [], lastState: .preheating)
    }

    public var isFinished: Bool { summary.outcome != .inProgress }

    /// Feeds a status received from the device. Returns true when the outcome changed.
    @discardableResult
    public mutating func ingest(_ s: DeviceStatus, at now: Date) -> Bool {
        guard !isFinished else { return false }
        let before = summary.outcome

        // A different session ID means the device rebooted (IDs restart at 0 after reset) or another
        // phone started a new session. Either way our session is over and did not complete.
        if s.sessionId != summary.deviceSessionId {
            summary.outcome = .failed
            summary.errorCode = s.error == .none ? .unexpectedReset : s.error
            summary.endedAt = now
            return true
        }

        summary.lastState = s.state
        summary.elapsedDryingSeconds = max(summary.elapsedDryingSeconds, s.elapsedDryingSeconds)
        if let h = s.humidityPercent {
            if summary.startHumidity == nil { summary.startHumidity = h }
            if s.state == .preheating || s.state == .drying || s.state == .cooldown || s.state == .completed {
                summary.endHumidity = h
            }
            summary.minHumidity = min(summary.minHumidity ?? h, h)
        }
        if let c = s.chamberCelsius {
            summary.maxTemperature = max(summary.maxTemperature ?? c, c)
            if s.state == .drying {
                tempSum += c
                tempCount += 1
                summary.averageDryingTemperature = tempSum / Double(tempCount)
            }
        }
        if s.state == .drying && summary.dryingStartedAt == nil {
            summary.dryingStartedAt = now.addingTimeInterval(-TimeInterval(s.elapsedDryingSeconds))
        }
        if lastSampleAt == nil || now.timeIntervalSince(lastSampleAt!) >= Self.sampleInterval {
            lastSampleAt = now
            if summary.samples.count < Self.maxSamples {
                summary.samples.append(SessionSample(t: now.timeIntervalSince(summary.startedAt), c: s.chamberCelsius, h: s.humidityPercent))
            }
        }

        switch s.state {
        case .completed:
            finish(.completed, at: now)
        case .idle:
            switch s.endReason {
            case .completed: finish(.completed, at: now)
            case .stoppedByUser, .stoppedOnDevice: finish(.stopped, at: now)
            case .error: finish(.failed, at: now, error: s.error)
            case .overTemperature: finish(.overTemperature, at: now, error: s.error)
            case .none:
                // Reset from another phone or the device button. If the full duration ran, it completed.
                finish(summary.elapsedDryingSeconds >= durationSeconds ? .completed : .stopped, at: now)
            }
        case .error:
            finish(.failed, at: now, error: s.error)
        case .overTemperature:
            finish(.overTemperature, at: now, error: s.error)
        default:
            break
        }
        return summary.outcome != before
    }

    /// Marks the session as never resolved (e.g. device removed or not seen again for 48 h).
    public mutating func markDisconnected(at now: Date) {
        guard !isFinished else { return }
        summary.outcome = .disconnected
        summary.endedAt = now
    }

    private mutating func finish(_ o: SessionOutcome, at now: Date, error: DeviceErrorCode = .none) {
        summary.outcome = o
        summary.errorCode = error
        summary.endedAt = now
    }
}
