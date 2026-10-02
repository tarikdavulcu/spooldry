import Foundation

// MARK: - Decoding errors

public enum ProtocolError: Error, Equatable, Sendable {
    case truncated(characteristic: String, expected: Int, actual: Int)
    case unsupportedProtocolVersion(UInt8)
    case unknownEnumValue(field: String, value: UInt8)
}

// MARK: - Fixed point helpers

public enum FixedPoint {
    /// Converts centi-degrees Celsius to °C. `Int16.min` means "invalid / no reading".
    public static func celsius(_ centi: Int16) -> Double? {
        centi == SpoolDryProtocol.invalidTemperature ? nil : Double(centi) / 100.0
    }

    /// Converts centi-percent relative humidity. `0xFFFF` means "invalid / no reading".
    public static func humidity(_ centi: UInt16) -> Double? {
        centi == SpoolDryProtocol.invalidHumidity ? nil : Double(centi) / 100.0
    }

    public static func centiCelsius(_ c: Double) -> Int16 {
        let v = (c * 100.0).rounded()
        return Int16(max(-32767, min(32767, v)))
    }
}

// MARK: - Device Status (5D0F000A) - 36 bytes

/// Complete, atomic device snapshot. This is the source of truth the app renders.
public struct DeviceStatus: Equatable, Sendable, Codable {
    public var protocolVersion: UInt8
    public var state: DeviceState
    public var error: DeviceErrorCode
    public var flags: StatusFlags
    public var chamberCelsius: Double?
    public var humidityPercent: Double?
    public var heaterCelsius: Double?
    public var targetCelsius: Double
    /// Seconds of drying left. `nil` when unknown (idle/error).
    public var remainingSeconds: UInt32?
    public var elapsedDryingSeconds: UInt32
    public var sessionId: UInt32
    public var material: MaterialCode
    public var heaterDutyPercent: UInt8
    public var fanRPM: UInt16
    public var uptimeSeconds: UInt32
    public var fanMode: FanMode
    public var endReason: SessionEndReason
    public var sequence: UInt16

    public init(protocolVersion: UInt8 = SpoolDryProtocol.protocolVersion, state: DeviceState, error: DeviceErrorCode = .none,
                flags: StatusFlags = [], chamberCelsius: Double?, humidityPercent: Double?, heaterCelsius: Double? = nil,
                targetCelsius: Double, remainingSeconds: UInt32?, elapsedDryingSeconds: UInt32 = 0, sessionId: UInt32 = 0,
                material: MaterialCode = .custom, heaterDutyPercent: UInt8 = 0, fanRPM: UInt16 = 0, uptimeSeconds: UInt32 = 0,
                fanMode: FanMode = .auto, endReason: SessionEndReason = .none, sequence: UInt16 = 0) {
        self.protocolVersion = protocolVersion
        self.state = state
        self.error = error
        self.flags = flags
        self.chamberCelsius = chamberCelsius
        self.humidityPercent = humidityPercent
        self.heaterCelsius = heaterCelsius
        self.targetCelsius = targetCelsius
        self.remainingSeconds = remainingSeconds
        self.elapsedDryingSeconds = elapsedDryingSeconds
        self.sessionId = sessionId
        self.material = material
        self.heaterDutyPercent = heaterDutyPercent
        self.fanRPM = fanRPM
        self.uptimeSeconds = uptimeSeconds
        self.fanMode = fanMode
        self.endReason = endReason
        self.sequence = sequence
    }

    public static let byteSize = 36

    /// Decodes the Device Status characteristic. Extra trailing bytes (future protocol additions) are ignored.
    public static func decode(_ data: Data) throws -> DeviceStatus {
        guard data.count >= byteSize else {
            throw ProtocolError.truncated(characteristic: "deviceStatus", expected: byteSize, actual: data.count)
        }
        var r = ByteReader(data)
        let version = try r.u8()
        guard version >= 1 else { throw ProtocolError.unsupportedProtocolVersion(version) }
        let stateRaw = try r.u8()
        guard let state = DeviceState(rawValue: stateRaw) else { throw ProtocolError.unknownEnumValue(field: "state", value: stateRaw) }
        let errorRaw = try r.u8()
        let error = DeviceErrorCode(rawValue: errorRaw) ?? .internal
        let flags = StatusFlags(rawValue: try r.u8())
        let chamber = FixedPoint.celsius(try r.i16())
        let humidity = FixedPoint.humidity(try r.u16())
        let heater = FixedPoint.celsius(try r.i16())
        let target = FixedPoint.celsius(try r.i16()) ?? 0
        let remainingRaw = try r.u32()
        let elapsed = try r.u32()
        let sessionId = try r.u32()
        let materialRaw = try r.u8()
        let duty = try r.u8()
        let rpm = try r.u16()
        let uptime = try r.u32()
        let fanRaw = try r.u8()
        let endRaw = try r.u8()
        let seq = try r.u16()
        return DeviceStatus(
            protocolVersion: version, state: state, error: error, flags: flags,
            chamberCelsius: chamber, humidityPercent: humidity, heaterCelsius: heater, targetCelsius: target,
            remainingSeconds: remainingRaw == SpoolDryProtocol.unknownRemaining ? nil : remainingRaw,
            elapsedDryingSeconds: elapsed, sessionId: sessionId,
            material: MaterialCode(rawValue: materialRaw) ?? .custom,
            heaterDutyPercent: duty, fanRPM: rpm, uptimeSeconds: uptime,
            fanMode: FanMode(rawValue: fanRaw) ?? .auto,
            endReason: SessionEndReason(rawValue: endRaw) ?? .none,
            sequence: seq)
    }

    /// Encodes the status exactly like the firmware (used by previews, demo mode and tests).
    public func encode() -> Data {
        var w = ByteWriter()
        w.u8(protocolVersion)
        w.u8(state.rawValue)
        w.u8(error.rawValue)
        w.u8(flags.rawValue)
        w.i16(chamberCelsius.map(FixedPoint.centiCelsius) ?? SpoolDryProtocol.invalidTemperature)
        w.u16(humidityPercent.map { UInt16(max(0, min(10000, ($0 * 100).rounded()))) } ?? SpoolDryProtocol.invalidHumidity)
        w.i16(heaterCelsius.map(FixedPoint.centiCelsius) ?? SpoolDryProtocol.invalidTemperature)
        w.i16(FixedPoint.centiCelsius(targetCelsius))
        w.u32(remainingSeconds ?? SpoolDryProtocol.unknownRemaining)
        w.u32(elapsedDryingSeconds)
        w.u32(sessionId)
        w.u8(material.rawValue)
        w.u8(heaterDutyPercent)
        w.u16(fanRPM)
        w.u32(uptimeSeconds)
        w.u8(fanMode.rawValue)
        w.u8(endReason.rawValue)
        w.u16(sequence)
        return w.data
    }

    public var isSessionActive: Bool { state == .preheating || state == .drying || state == .cooldown }
    public var isHeating: Bool { state == .preheating || state == .drying }
}

// MARK: - Device Info (5D0F0002) - 23 bytes

public enum DeviceResetCause: UInt8, Sendable, Codable {
    case unknown = 0, powerOn = 1, software = 2, panic = 3, watchdog = 4, brownout = 5, other = 6

    public var isUnexpected: Bool { self == .panic || self == .watchdog || self == .brownout }
}

public struct DeviceInfo: Equatable, Sendable, Codable {
    public var protocolVersion: UInt8
    public var hardwareRevision: UInt8
    public var deviceId: Data
    public var firmwareVersion: String
    public var minTargetCelsius: Double
    public var maxTargetCelsius: Double
    public var maxDurationSeconds: UInt32
    public var capabilities: DeviceCapabilities
    public var resetCause: DeviceResetCause
    public var lastFault: DeviceErrorCode

    public static let byteSize = 23

    public init(protocolVersion: UInt8, hardwareRevision: UInt8, deviceId: Data, firmwareVersion: String,
                minTargetCelsius: Double, maxTargetCelsius: Double, maxDurationSeconds: UInt32,
                capabilities: DeviceCapabilities, resetCause: DeviceResetCause, lastFault: DeviceErrorCode) {
        self.protocolVersion = protocolVersion
        self.hardwareRevision = hardwareRevision
        self.deviceId = deviceId
        self.firmwareVersion = firmwareVersion
        self.minTargetCelsius = minTargetCelsius
        self.maxTargetCelsius = maxTargetCelsius
        self.maxDurationSeconds = maxDurationSeconds
        self.capabilities = capabilities
        self.resetCause = resetCause
        self.lastFault = lastFault
    }

    public static func decode(_ data: Data) throws -> DeviceInfo {
        guard data.count >= byteSize else {
            throw ProtocolError.truncated(characteristic: "deviceInfo", expected: byteSize, actual: data.count)
        }
        var r = ByteReader(data)
        let pv = try r.u8()
        let hw = try r.u8()
        let id = Data(try r.bytes(6))
        let major = try r.u8(), minor = try r.u8(), patch = try r.u8()
        let minT = FixedPoint.celsius(try r.i16()) ?? 35
        let maxT = FixedPoint.celsius(try r.i16()) ?? 70
        let maxD = try r.u32()
        let caps = DeviceCapabilities(rawValue: try r.u16())
        let reset = DeviceResetCause(rawValue: try r.u8()) ?? .other
        let fault = DeviceErrorCode(rawValue: try r.u8()) ?? .internal
        return DeviceInfo(protocolVersion: pv, hardwareRevision: hw, deviceId: id, firmwareVersion: "\(major).\(minor).\(patch)",
                          minTargetCelsius: minT, maxTargetCelsius: maxT, maxDurationSeconds: maxD,
                          capabilities: caps, resetCause: reset, lastFault: fault)
    }

    /// True when the app understands this device's protocol major version.
    public var isProtocolSupported: Bool { protocolVersion == SpoolDryProtocol.protocolVersion }

    public var shortId: String {
        let hex = deviceId.hexString.uppercased()
        return String(hex.suffix(4))
    }
}

// MARK: - Drying Session (5D0F0007) - 20 bytes

public struct DryingSessionInfo: Equatable, Sendable, Codable {
    public var sessionId: UInt32
    public var material: MaterialCode
    public var endReason: SessionEndReason
    public var targetCelsius: Double
    public var durationSeconds: UInt32
    public var elapsedDryingSeconds: UInt32
    public var startDate: Date?

    public static let byteSize = 20

    public init(sessionId: UInt32, material: MaterialCode, endReason: SessionEndReason, targetCelsius: Double,
                durationSeconds: UInt32, elapsedDryingSeconds: UInt32, startDate: Date?) {
        self.sessionId = sessionId
        self.material = material
        self.endReason = endReason
        self.targetCelsius = targetCelsius
        self.durationSeconds = durationSeconds
        self.elapsedDryingSeconds = elapsedDryingSeconds
        self.startDate = startDate
    }

    public static func decode(_ data: Data) throws -> DryingSessionInfo {
        guard data.count >= byteSize else {
            throw ProtocolError.truncated(characteristic: "dryingSession", expected: byteSize, actual: data.count)
        }
        var r = ByteReader(data)
        let sid = try r.u32()
        let m = MaterialCode(rawValue: try r.u8()) ?? .custom
        let end = SessionEndReason(rawValue: try r.u8()) ?? .none
        let t = FixedPoint.celsius(try r.i16()) ?? 0
        let dur = try r.u32()
        let el = try r.u32()
        let start = try r.u32()
        return DryingSessionInfo(sessionId: sid, material: m, endReason: end, targetCelsius: t, durationSeconds: dur,
                                 elapsedDryingSeconds: el,
                                 startDate: start == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(start)))
    }
}

// MARK: - Small characteristics

public struct TemperatureReading: Equatable, Sendable {
    public var chamberCelsius: Double?
    public var heaterCelsius: Double?
    public init(chamberCelsius: Double?, heaterCelsius: Double?) {
        self.chamberCelsius = chamberCelsius
        self.heaterCelsius = heaterCelsius
    }

    public static func decode(_ data: Data) throws -> TemperatureReading {
        guard data.count >= 4 else { throw ProtocolError.truncated(characteristic: "temperature", expected: 4, actual: data.count) }
        var r = ByteReader(data)
        return TemperatureReading(chamberCelsius: FixedPoint.celsius(try r.i16()), heaterCelsius: FixedPoint.celsius(try r.i16()))
    }
}

public struct HumidityReading: Equatable, Sendable {
    public var percent: Double?
    public init(percent: Double?) { self.percent = percent }

    public static func decode(_ data: Data) throws -> HumidityReading {
        guard data.count >= 2 else { throw ProtocolError.truncated(characteristic: "humidity", expected: 2, actual: data.count) }
        var r = ByteReader(data)
        return HumidityReading(percent: FixedPoint.humidity(try r.u16()))
    }
}

public struct HeaterState: Equatable, Sendable {
    public var relayClosed: Bool
    public var outputActive: Bool
    public var dutyPercent: UInt8

    public init(relayClosed: Bool, outputActive: Bool, dutyPercent: UInt8) {
        self.relayClosed = relayClosed
        self.outputActive = outputActive
        self.dutyPercent = dutyPercent
    }

    public static func decode(_ data: Data) throws -> HeaterState {
        guard data.count >= 2 else { throw ProtocolError.truncated(characteristic: "heaterState", expected: 2, actual: data.count) }
        var r = ByteReader(data)
        let f = try r.u8()
        return HeaterState(relayClosed: f & 0x01 != 0, outputActive: f & 0x02 != 0, dutyPercent: try r.u8())
    }
}

public struct FanState: Equatable, Sendable {
    public var mode: FanMode
    public var isOn: Bool
    public var rpm: UInt16

    public init(mode: FanMode, isOn: Bool, rpm: UInt16) {
        self.mode = mode
        self.isOn = isOn
        self.rpm = rpm
    }

    public static func decode(_ data: Data) throws -> FanState {
        guard data.count >= 4 else { throw ProtocolError.truncated(characteristic: "fanState", expected: 4, actual: data.count) }
        var r = ByteReader(data)
        let m = FanMode(rawValue: try r.u8()) ?? .auto
        let on = try r.u8() != 0
        return FanState(mode: m, isOn: on, rpm: try r.u16())
    }
}

public enum RemainingTimeReading {
    public static func decode(_ data: Data) throws -> UInt32? {
        guard data.count >= 4 else { throw ProtocolError.truncated(characteristic: "remainingTime", expected: 4, actual: data.count) }
        var r = ByteReader(data)
        let v = try r.u32()
        return v == SpoolDryProtocol.unknownRemaining ? nil : v
    }
}

public enum TargetTemperatureReading {
    public static func decode(_ data: Data) throws -> Double? {
        guard data.count >= 2 else { throw ProtocolError.truncated(characteristic: "targetTemp", expected: 2, actual: data.count) }
        var r = ByteReader(data)
        return FixedPoint.celsius(try r.i16())
    }
}

// MARK: - Commands (5D0F000B)

public enum DeviceCommand: Equatable, Sendable {
    case startSession(material: MaterialCode, targetCelsius: Double, durationSeconds: UInt32, now: Date, fanMode: FanMode)
    case stopSession
    case setTargetTemperature(celsius: Double)
    case setDuration(seconds: UInt32)
    case setFilament(MaterialCode)
    case setFanMode(FanMode)
    case requestStatus
    case resetSession
    case identify
    case setDeviceName(String)

    public var opcode: Opcode {
        switch self {
        case .startSession: return .startSession
        case .stopSession: return .stopSession
        case .setTargetTemperature: return .setTargetTemp
        case .setDuration: return .setDuration
        case .setFilament: return .setFilament
        case .setFanMode: return .setFanMode
        case .requestStatus: return .requestStatus
        case .resetSession: return .resetSession
        case .identify: return .identify
        case .setDeviceName: return .setDeviceName
        }
    }

    public enum ValidationError: Error, Equatable {
        case targetOutOfRange
        case durationOutOfRange
        case invalidName
    }

    /// Payload bytes (without the 4-byte header). Validates ranges against protocol limits.
    public func payload() throws -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case let .startSession(material, target, duration, now, fan):
            let centi = try Self.validatedTarget(target)
            try Self.validateDuration(duration)
            w.u8(material.rawValue)
            w.i16(centi)
            w.u32(duration)
            w.u32(UInt32(max(0, min(Double(UInt32.max), now.timeIntervalSince1970.rounded(.down)))))
            w.u8(fan.rawValue)
        case .stopSession, .requestStatus, .resetSession, .identify:
            break
        case let .setTargetTemperature(c):
            w.i16(try Self.validatedTarget(c))
        case let .setDuration(s):
            try Self.validateDuration(s)
            w.u32(s)
        case let .setFilament(m):
            w.u8(m.rawValue)
        case let .setFanMode(f):
            w.u8(f.rawValue)
        case let .setDeviceName(name):
            let bytes = Array(name.utf8)
            guard !bytes.isEmpty, bytes.count <= 20, !bytes.contains(where: { $0 < 0x20 || $0 == 0x7F }) else {
                throw ValidationError.invalidName
            }
            w.append(bytes)
        }
        return w.bytes
    }

    /// Full frame: [version][opcode][seq][len][payload].
    public func frame(sequence: UInt8) throws -> Data {
        let p = try payload()
        var w = ByteWriter()
        w.u8(SpoolDryProtocol.protocolVersion)
        w.u8(opcode.rawValue)
        w.u8(sequence)
        w.u8(UInt8(p.count))
        w.append(p)
        return w.data
    }

    private static func validatedTarget(_ c: Double) throws -> Int16 {
        let centi = FixedPoint.centiCelsius(c)
        guard centi >= SpoolDryProtocol.minTargetCentiC, centi <= SpoolDryProtocol.maxTargetCentiC else {
            throw ValidationError.targetOutOfRange
        }
        return centi
    }

    private static func validateDuration(_ s: UInt32) throws {
        guard s >= SpoolDryProtocol.minDurationSec, s <= SpoolDryProtocol.maxDurationSec else {
            throw ValidationError.durationOutOfRange
        }
    }
}

// MARK: - Command Response (5D0F000C)

public struct CommandResponse: Equatable, Sendable {
    public var type: ResponseType
    public var sequence: UInt8
    public var opcodeRaw: UInt8
    public var result: ResultCode
    public var payload: [UInt8]

    public init(type: ResponseType, sequence: UInt8, opcodeRaw: UInt8, result: ResultCode, payload: [UInt8]) {
        self.type = type
        self.sequence = sequence
        self.opcodeRaw = opcodeRaw
        self.result = result
        self.payload = payload
    }

    /// Encodes like the firmware (demo device and tests).
    public func encode() -> Data {
        var w = ByteWriter()
        w.u8(SpoolDryProtocol.protocolVersion)
        w.u8(type.rawValue)
        w.u8(sequence)
        w.u8(opcodeRaw)
        w.u8(result.rawValue)
        w.u8(UInt8(min(payload.count, 10)))
        w.append(Array(payload.prefix(10)))
        return w.data
    }

    public var isAck: Bool { type == .ack && result == .ok }

    public static func decode(_ data: Data) throws -> CommandResponse {
        guard data.count >= 6 else { throw ProtocolError.truncated(characteristic: "commandResponse", expected: 6, actual: data.count) }
        var r = ByteReader(data)
        let version = try r.u8()
        guard version >= 1 else { throw ProtocolError.unsupportedProtocolVersion(version) }
        let typeRaw = try r.u8()
        guard let type = ResponseType(rawValue: typeRaw) else { throw ProtocolError.unknownEnumValue(field: "responseType", value: typeRaw) }
        let seq = try r.u8()
        let op = try r.u8()
        let result = ResultCode(rawValue: try r.u8()) ?? .internalError
        let len = Int(try r.u8())
        let payload = try r.bytes(min(len, r.remaining))
        return CommandResponse(type: type, sequence: seq, opcodeRaw: op, result: result, payload: payload)
    }

    /// START_SESSION acknowledgement payload.
    public var startAck: (sessionId: UInt32, deviceTime: Date)? {
        guard type == .ack, opcodeRaw == Opcode.startSession.rawValue, payload.count >= 8 else { return nil }
        var r = ByteReader(payload)
        guard let sid = try? r.u32(), let t = try? r.u32() else { return nil }
        return (sid, Date(timeIntervalSince1970: TimeInterval(t)))
    }

    /// NACK payload describing the device state at rejection time (when provided).
    public var rejectionState: (state: DeviceState, error: DeviceErrorCode)? {
        guard type == .nack, payload.count >= 2, let s = DeviceState(rawValue: payload[0]) else { return nil }
        return (s, DeviceErrorCode(rawValue: payload[1]) ?? .internal)
    }
}
