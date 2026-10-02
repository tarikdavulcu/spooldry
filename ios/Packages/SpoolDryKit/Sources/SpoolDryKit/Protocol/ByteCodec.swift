import Foundation

/// Little-endian reader for BLE payloads. All reads are bounds-checked.
public struct ByteReader {
    public enum ReadError: Error, Equatable {
        case truncated(needed: Int, available: Int)
    }

    private let bytes: [UInt8]
    public private(set) var offset: Int = 0

    public init(_ data: Data) { self.bytes = [UInt8](data) }
    public init(_ bytes: [UInt8]) { self.bytes = bytes }

    public var remaining: Int { bytes.count - offset }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard remaining >= n else { throw ReadError.truncated(needed: n, available: remaining) }
        defer { offset += n }
        return bytes[offset..<(offset + n)]
    }

    public mutating func u8() throws -> UInt8 { try take(1).first! }

    public mutating func u16() throws -> UInt16 {
        let s = try take(2)
        return UInt16(s[s.startIndex]) | (UInt16(s[s.startIndex + 1]) << 8)
    }

    public mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    public mutating func u32() throws -> UInt32 {
        let s = try take(4)
        var v: UInt32 = 0
        for (i, b) in s.enumerated() { v |= UInt32(b) << (8 * UInt32(i)) }
        return v
    }

    public mutating func bytes(_ n: Int) throws -> [UInt8] { Array(try take(n)) }
}

/// Little-endian writer for BLE payloads.
public struct ByteWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func u8(_ v: UInt8) { bytes.append(v) }
    public mutating func u16(_ v: UInt16) {
        bytes.append(UInt8(v & 0xFF))
        bytes.append(UInt8(v >> 8))
    }
    public mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    public mutating func u32(_ v: UInt32) {
        for i in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
    }
    public mutating func append(_ b: [UInt8]) { bytes.append(contentsOf: b) }

    public var data: Data { Data(bytes) }
}

public extension Data {
    /// Lowercase hex representation (used for device IDs, logs and tests).
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    /// Parses a hex string ("0a1b..."). Returns nil for odd length or invalid characters.
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            out.append(b)
            i += 2
        }
        self.init(out)
    }
}
