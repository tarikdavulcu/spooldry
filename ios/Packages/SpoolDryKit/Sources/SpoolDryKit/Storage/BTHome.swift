import Foundation

/// One decoded BTHome v2 advertisement (https://bthome.io/format/).
///
/// BTHome is an open format used by off-the-shelf Bluetooth thermo-hygrometers (for example Shelly BLU H&T,
/// or Xiaomi/Telink sensors running the open PVVX/ATC firmware in BTHome mode). The sensors broadcast their
/// readings as Bluetooth LE service data with the 16-bit UUID 0xFCD2; no pairing or connection is needed.
public struct BTHomeReading: Equatable, Sendable {
    public var temperatureCelsius: Double?
    public var humidityPercent: Double?
    public var batteryPercent: Int?
    public var packetID: UInt8?
    /// Encrypted advertisements cannot be read without the sensor's bind key; SpoolDry reports them as such.
    public var isEncrypted: Bool
    public var isTriggerBased: Bool

    public init(temperatureCelsius: Double? = nil, humidityPercent: Double? = nil, batteryPercent: Int? = nil,
                packetID: UInt8? = nil, isEncrypted: Bool = false, isTriggerBased: Bool = false) {
        self.temperatureCelsius = temperatureCelsius
        self.humidityPercent = humidityPercent
        self.batteryPercent = batteryPercent
        self.packetID = packetID
        self.isEncrypted = isEncrypted
        self.isTriggerBased = isTriggerBased
    }

    /// True when the advertisement carries a humidity value SpoolDry can use for a dry box.
    public var hasHumidity: Bool { humidityPercent != nil }
}

public enum BTHomeParser {
    /// 16-bit service UUID BTHome uses for its service data.
    public static let serviceUUID = "FCD2"

    /// Payload length in bytes for every fixed-size BTHome v2 object id. Unknown ids stop parsing,
    /// because the format has no per-object length field.
    static let objectLengths: [UInt8: Int] = {
        var m: [UInt8: Int] = [
            0x00: 1, 0x01: 1, 0x02: 2, 0x03: 2, 0x04: 3, 0x05: 3, 0x06: 2, 0x07: 2, 0x08: 2, 0x09: 1,
            0x0A: 3, 0x0B: 3, 0x0C: 2, 0x0D: 2, 0x0E: 2, 0x12: 2, 0x13: 2, 0x14: 2,
            0x2E: 1, 0x2F: 1, 0x3A: 1, 0x3C: 2, 0x3D: 2, 0x3E: 4, 0x3F: 2, 0x40: 2, 0x41: 2, 0x42: 3,
            0x43: 2, 0x44: 2, 0x45: 2, 0x46: 1, 0x47: 2, 0x48: 2, 0x49: 2, 0x4A: 2, 0x4B: 3, 0x4C: 4,
            0x4D: 4, 0x4E: 4, 0x4F: 4, 0x50: 4, 0x51: 2, 0x52: 2, 0x55: 4, 0x56: 2, 0x57: 1, 0x58: 1,
            0x59: 1, 0x5A: 2, 0x5B: 4, 0x5C: 4, 0x5D: 2, 0x5E: 2, 0x5F: 2, 0x60: 1, 0x61: 2, 0x62: 4,
            0x63: 4, 0xF0: 2, 0xF1: 4, 0xF2: 3,
        ]
        for id in UInt8(0x0F)...UInt8(0x11) { m[id] = 1 }   // binary sensors
        for id in UInt8(0x15)...UInt8(0x2D) { m[id] = 1 }   // binary sensors
        return m
    }()

    /// Decodes the service-data payload (the bytes after the 0xFCD2 UUID). Returns nil for anything that is not BTHome v2.
    public static func parse(_ data: Data) -> BTHomeReading? {
        let b = [UInt8](data)
        guard let info = b.first else { return nil }
        guard (info >> 5) & 0x07 == 2 else { return nil }   // version bits 5-7 must be 2
        var reading = BTHomeReading(isEncrypted: info & 0x01 != 0, isTriggerBased: info & 0x04 != 0)
        if reading.isEncrypted { return reading }

        var i = 1
        while i < b.count {
            let id = b[i]
            i += 1
            let length: Int
            if id == 0x53 || id == 0x54 {   // text / raw: one length byte, then payload
                guard i < b.count else { break }
                length = Int(b[i]) + 1
            } else if let fixed = objectLengths[id] {
                length = fixed
            } else {
                break   // unknown object: the rest cannot be located safely
            }
            guard i + length <= b.count else { break }
            let p = Array(b[i ..< i + length])
            switch id {
            case 0x00: reading.packetID = p[0]
            case 0x01: reading.batteryPercent = Int(p[0])
            case 0x02: reading.temperatureCelsius = Double(Int16(bitPattern: u16(p))) * 0.01
            case 0x45: reading.temperatureCelsius = Double(Int16(bitPattern: u16(p))) * 0.1
            case 0x57: reading.temperatureCelsius = Double(Int8(bitPattern: p[0]))
            case 0x03: reading.humidityPercent = Double(u16(p)) * 0.01
            case 0x2E: reading.humidityPercent = Double(p[0])
            default: break
            }
            i += length
        }
        if let h = reading.humidityPercent, !(0...100).contains(h) { reading.humidityPercent = nil }
        return reading
    }

    private static func u16(_ p: [UInt8]) -> UInt16 { UInt16(p[0]) | UInt16(p[1]) << 8 }
}
