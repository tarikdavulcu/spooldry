// GENERATED FILE - DO NOT EDIT. Source: protocol/spooldry-ble-v1.json (tools/gen_protocol.py)
import Foundation

public enum SpoolDryProtocol {
    public static let protocolVersion: UInt8 = 1
    public static let referenceFirmwareVersion = "1.0.0"
    public static let advertisedNamePrefix = "SpoolDry-"
    public static let serviceUUID = "5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44"
    public static let minTargetCentiC: Int16 = 3500
    public static let maxTargetCentiC: Int16 = 7000
    public static let minDurationSec: UInt32 = 900
    public static let maxDurationSec: UInt32 = 172800
    public static let invalidTemperature: Int16 = Int16.min
    public static let invalidHumidity: UInt16 = 65535
    public static let unknownRemaining: UInt32 = 4294967295
}

/// GATT characteristics of the SpoolDry Device Service.
public enum SpoolDryCharacteristic: String, CaseIterable, Sendable {
    case deviceInfo = "5D0F0002-2B7E-4C8A-9B1E-53504F4F4C44"
    case temperature = "5D0F0003-2B7E-4C8A-9B1E-53504F4F4C44"
    case humidity = "5D0F0004-2B7E-4C8A-9B1E-53504F4F4C44"
    case heaterState = "5D0F0005-2B7E-4C8A-9B1E-53504F4F4C44"
    case fanState = "5D0F0006-2B7E-4C8A-9B1E-53504F4F4C44"
    case dryingSession = "5D0F0007-2B7E-4C8A-9B1E-53504F4F4C44"
    case targetTemp = "5D0F0008-2B7E-4C8A-9B1E-53504F4F4C44"
    case remainingTime = "5D0F0009-2B7E-4C8A-9B1E-53504F4F4C44"
    case deviceStatus = "5D0F000A-2B7E-4C8A-9B1E-53504F4F4C44"
    case command = "5D0F000B-2B7E-4C8A-9B1E-53504F4F4C44"
    case commandResponse = "5D0F000C-2B7E-4C8A-9B1E-53504F4F4C44"
    case firmwareVersion = "5D0F000D-2B7E-4C8A-9B1E-53504F4F4C44"

    public var expectedSize: Int {
        switch self {
        case .deviceInfo: return 23
        case .temperature: return 4
        case .humidity: return 2
        case .heaterState: return 2
        case .fanState: return 4
        case .dryingSession: return 20
        case .targetTemp: return 2
        case .remainingTime: return 4
        case .deviceStatus: return 36
        case .command: return 36
        case .commandResponse: return 16
        case .firmwareVersion: return 16
        }
    }

    public var displayName: String {
        switch self {
        case .deviceInfo: return "Device Info"
        case .temperature: return "Temperature"
        case .humidity: return "Humidity"
        case .heaterState: return "Heater State"
        case .fanState: return "Fan State"
        case .dryingSession: return "Drying Session"
        case .targetTemp: return "Target Temperature"
        case .remainingTime: return "Remaining Time"
        case .deviceStatus: return "Device Status"
        case .command: return "Command"
        case .commandResponse: return "Command Response"
        case .firmwareVersion: return "Firmware Version"
        }
    }
}

/// Shared device/link state machine. 0-2 are app-side link states.
public enum DeviceState: UInt8, CaseIterable, Sendable, Codable {
    case disconnected = 0
    case connecting = 1
    case connected = 2
    case idle = 3
    case preheating = 4
    case drying = 5
    case cooldown = 6
    case completed = 7
    case error = 8
    case overTemperature = 9
}

public enum Opcode: UInt8, CaseIterable, Sendable, Codable {
    case startSession = 1
    case stopSession = 2
    case setTargetTemp = 3
    case setDuration = 4
    case setFilament = 5
    case setFanMode = 6
    case requestStatus = 7
    case resetSession = 8
    case identify = 9
    case setDeviceName = 10
}

public enum ResponseType: UInt8, CaseIterable, Sendable, Codable {
    case ack = 128
    case nack = 129
}

public enum ResultCode: UInt8, CaseIterable, Sendable, Codable {
    case ok = 0
    case unknownOpcode = 1
    case badLength = 2
    case unsupportedVersion = 3
    case invalidParameter = 4
    case busy = 5
    case notAllowedInState = 6
    case sensorFault = 7
    case overTemperatureLock = 8
    case internalError = 9
}

public enum DeviceErrorCode: UInt8, CaseIterable, Sendable, Codable {
    case none = 0
    case sensorI2c = 1
    case sensorCrc = 2
    case sensorRange = 3
    case ntcOpen = 4
    case ntcShort = 5
    case overTempChamber = 6
    case overTempHeater = 7
    case preheatTimeout = 8
    case heatingIneffective = 9
    case heaterStuckOn = 10
    case fanFailure = 11
    case sessionTimeLimit = 12
    case unexpectedReset = 13
    case `internal` = 14
}

public enum FanMode: UInt8, CaseIterable, Sendable, Codable {
    case auto = 0
    case on = 1
    case off = 2
}

public enum SessionEndReason: UInt8, CaseIterable, Sendable, Codable {
    case none = 0
    case completed = 1
    case stoppedByUser = 2
    case stoppedOnDevice = 3
    case error = 4
    case overTemperature = 5
}

public enum MaterialCode: UInt8, CaseIterable, Sendable, Codable {
    case custom = 0
    case pla = 1
    case petg = 2
    case abs = 3
    case asa = 4
    case tpu = 5
    case pa = 6
    case pc = 7
    case pva = 8
    case bvoh = 9
    case peek = 10
    case pei = 11
    case pps = 12
    case paCf = 13
    case paGf = 14
    case petgCf = 15
    case plaCf = 16
    case pcCf = 17
    case asaCf = 18
    case ppsCf = 19
}

public struct StatusFlags: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let heaterRelay = StatusFlags(rawValue: 1 << 0)
    public static let heaterOutput = StatusFlags(rawValue: 1 << 1)
    public static let fanOn = StatusFlags(rawValue: 1 << 2)
    public static let clientConnected = StatusFlags(rawValue: 1 << 3)
    public static let chamberSensorOk = StatusFlags(rawValue: 1 << 4)
    public static let heaterSensorOk = StatusFlags(rawValue: 1 << 5)
    public static let sessionActive = StatusFlags(rawValue: 1 << 6)
    public static let timeSynced = StatusFlags(rawValue: 1 << 7)
}

public struct DeviceCapabilities: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let heaterNtc = DeviceCapabilities(rawValue: 1 << 0)
    public static let fanTach = DeviceCapabilities(rawValue: 1 << 1)
    public static let safetyRelay = DeviceCapabilities(rawValue: 1 << 2)
    public static let identifyLed = DeviceCapabilities(rawValue: 1 << 3)
    public static let localButton = DeviceCapabilities(rawValue: 1 << 4)
    public static let otaBle = DeviceCapabilities(rawValue: 1 << 5)
}
