import Foundation

/// What Live Activities, widgets and the dashboard display. Derived ONLY from data the device reported:
/// no simulated progress. While preheating there is no countdown, because the device has not started
/// the drying timer yet.
public struct DryingDisplayState: Codable, Hashable, Sendable {
    public var state: DeviceState
    public var errorCode: DeviceErrorCode
    public var chamberCelsius: Double?
    public var humidityPercent: Double?
    public var targetCelsius: Double
    /// End of the drying timer, computed from the device's remaining seconds when the status arrived.
    /// Only set in DRYING, so `Text(timerInterval:)` counts down locally between BLE updates.
    public var dryingEndDate: Date?
    public var remainingSeconds: UInt32?
    public var durationSeconds: UInt32
    /// 0...1 drying progress; nil while preheating or when unknown.
    public var progress: Double?
    /// When the device data was received.
    public var updatedAt: Date

    public init(state: DeviceState, errorCode: DeviceErrorCode = .none, chamberCelsius: Double?, humidityPercent: Double?,
                targetCelsius: Double, dryingEndDate: Date?, remainingSeconds: UInt32?, durationSeconds: UInt32,
                progress: Double?, updatedAt: Date) {
        self.state = state
        self.errorCode = errorCode
        self.chamberCelsius = chamberCelsius
        self.humidityPercent = humidityPercent
        self.targetCelsius = targetCelsius
        self.dryingEndDate = dryingEndDate
        self.remainingSeconds = remainingSeconds
        self.durationSeconds = durationSeconds
        self.progress = progress
        self.updatedAt = updatedAt
    }

    public static func from(status s: DeviceStatus, durationSeconds: UInt32, receivedAt now: Date) -> DryingDisplayState {
        var end: Date?
        var progress: Double?
        let duration = max(durationSeconds, 1)
        switch s.state {
        case .drying:
            if let rem = s.remainingSeconds {
                end = now.addingTimeInterval(TimeInterval(rem))
                progress = min(1, max(0, Double(duration - min(rem, duration)) / Double(duration)))
            }
        case .cooldown, .completed:
            progress = s.endReason == .completed ? 1 : min(1, Double(s.elapsedDryingSeconds) / Double(duration))
        default:
            progress = nil
        }
        return DryingDisplayState(state: s.state, errorCode: s.error, chamberCelsius: s.chamberCelsius,
                                  humidityPercent: s.humidityPercent, targetCelsius: s.targetCelsius, dryingEndDate: end,
                                  remainingSeconds: s.remainingSeconds, durationSeconds: durationSeconds,
                                  progress: progress, updatedAt: now)
    }

    /// Data older than this is labelled "last update" instead of shown as live.
    public static let staleAfter: TimeInterval = 120

    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(updatedAt) > Self.staleAfter }

    public var isTerminal: Bool {
        state == .completed || state == .error || state == .overTemperature || state == .idle
    }

    /// Remaining time at `now`, extrapolated from the device's last report (drying only).
    public func remaining(at now: Date) -> TimeInterval? {
        if let end = dryingEndDate { return max(0, end.timeIntervalSince(now)) }
        if state == .preheating { return remainingSeconds.map(TimeInterval.init) }
        return nil
    }
}

public extension DeviceState {
    var localizationKey: String {
        switch self {
        case .disconnected: return "state.disconnected"
        case .connecting: return "state.connecting"
        case .connected: return "state.connected"
        case .idle: return "state.idle"
        case .preheating: return "state.preheating"
        case .drying: return "state.drying"
        case .cooldown: return "state.cooldown"
        case .completed: return "state.completed"
        case .error: return "state.error"
        case .overTemperature: return "state.overTemperature"
        }
    }

    /// SF Symbol for the state (always shown with text: never color alone).
    var symbolName: String {
        switch self {
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .connected: return "checkmark.circle"
        case .idle: return "pause.circle"
        case .preheating: return "thermometer.sun"
        case .drying: return "humidity"
        case .cooldown: return "wind"
        case .completed: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .overTemperature: return "thermometer.high"
        }
    }
}

public extension DeviceErrorCode {
    var localizationKey: String {
        switch self {
        case .none: return "error.none"
        case .sensorI2c: return "error.sensorI2c"
        case .sensorCrc: return "error.sensorCrc"
        case .sensorRange: return "error.sensorRange"
        case .ntcOpen: return "error.ntcOpen"
        case .ntcShort: return "error.ntcShort"
        case .overTempChamber: return "error.overTempChamber"
        case .overTempHeater: return "error.overTempHeater"
        case .preheatTimeout: return "error.preheatTimeout"
        case .heatingIneffective: return "error.heatingIneffective"
        case .heaterStuckOn: return "error.heaterStuckOn"
        case .fanFailure: return "error.fanFailure"
        case .sessionTimeLimit: return "error.sessionTimeLimit"
        case .unexpectedReset: return "error.unexpectedReset"
        case .internal: return "error.internal"
        }
    }
}

public extension ResultCode {
    var localizationKey: String {
        switch self {
        case .ok: return "result.ok"
        case .unknownOpcode: return "result.unknownOpcode"
        case .badLength: return "result.badLength"
        case .unsupportedVersion: return "result.unsupportedVersion"
        case .invalidParameter: return "result.invalidParameter"
        case .busy: return "result.busy"
        case .notAllowedInState: return "result.notAllowedInState"
        case .sensorFault: return "result.sensorFault"
        case .overTemperatureLock: return "result.overTemperatureLock"
        case .internalError: return "result.internalError"
        }
    }
}
