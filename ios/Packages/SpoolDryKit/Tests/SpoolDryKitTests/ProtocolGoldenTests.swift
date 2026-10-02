import XCTest
@testable import SpoolDryKit

/// Cross-language conformance: these bytes were produced by the ESP32 firmware codec
/// (esp32/test/host/golden_vectors.cpp). If firmware and app ever disagree, these tests fail.
final class ProtocolGoldenTests: XCTestCase {
    struct Golden: Decodable {
        let protocolVersion: Int
        let deviceStatus: String
        let deviceStatusInvalidSensors: String
        let temperature: String
        let humidity: String
        let heaterState: String
        let fanState: String
        let dryingSession: String
        let targetTemp: String
        let remainingTime: String
        let deviceInfo: String
        let commands: [String: String]
        let responseStartAck: String
        let responseStartNackOverTemp: String
    }

    private func golden() throws -> Golden {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "golden-vectors-v1", withExtension: "json", subdirectory: "Resources"))
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    private func hex(_ s: String) throws -> Data { try XCTUnwrap(Data(hexString: s)) }

    func testProtocolVersionMatchesFirmware() throws {
        XCTAssertEqual(try golden().protocolVersion, Int(SpoolDryProtocol.protocolVersion))
    }

    func testDecodeDeviceStatus() throws {
        let s = try DeviceStatus.decode(hex(golden().deviceStatus))
        XCTAssertEqual(s.state, .drying)
        XCTAssertEqual(s.error, DeviceErrorCode.none)
        XCTAssertEqual(s.flags, [.heaterRelay, .heaterOutput, .fanOn, .clientConnected, .chamberSensorOk, .heaterSensorOk, .sessionActive, .timeSynced])
        XCTAssertEqual(try XCTUnwrap(s.chamberCelsius), 67.20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.humidityPercent), 18.40, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(s.heaterCelsius), 71.05, accuracy: 0.001)
        XCTAssertEqual(s.targetCelsius, 70.0, accuracy: 0.001)
        XCTAssertEqual(s.remainingSeconds, 9660)
        XCTAssertEqual(s.elapsedDryingSeconds, 19140)
        XCTAssertEqual(s.sessionId, 42)
        XCTAssertEqual(s.material, .paCf)
        XCTAssertEqual(s.heaterDutyPercent, 37)
        XCTAssertEqual(s.fanRPM, 6800)
        XCTAssertEqual(s.uptimeSeconds, 23456)
        XCTAssertEqual(s.fanMode, .auto)
        XCTAssertEqual(s.endReason, SessionEndReason.none)
        XCTAssertEqual(s.sequence, 513)
    }

    func testDeviceStatusRoundTripIsByteExact() throws {
        let bytes = try hex(golden().deviceStatus)
        XCTAssertEqual(try DeviceStatus.decode(bytes).encode(), bytes)
        let invalid = try hex(golden().deviceStatusInvalidSensors)
        XCTAssertEqual(try DeviceStatus.decode(invalid).encode(), invalid)
    }

    func testInvalidSensorsDecodeAsNil() throws {
        let s = try DeviceStatus.decode(hex(golden().deviceStatusInvalidSensors))
        XCTAssertEqual(s.state, .idle)
        XCTAssertNil(s.chamberCelsius)
        XCTAssertNil(s.humidityPercent)
        XCTAssertNil(s.heaterCelsius)
        XCTAssertNil(s.remainingSeconds)
    }

    func testDecodeIndividualCharacteristics() throws {
        let g = try golden()
        let t = try TemperatureReading.decode(hex(g.temperature))
        XCTAssertEqual(try XCTUnwrap(t.chamberCelsius), 67.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(t.heaterCelsius), 71.05, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(HumidityReading.decode(hex(g.humidity)).percent), 18.4, accuracy: 0.001)
        let h = try HeaterState.decode(hex(g.heaterState))
        XCTAssertTrue(h.relayClosed)
        XCTAssertTrue(h.outputActive)
        XCTAssertEqual(h.dutyPercent, 37)
        let f = try FanState.decode(hex(g.fanState))
        XCTAssertEqual(f.mode, .auto)
        XCTAssertTrue(f.isOn)
        XCTAssertEqual(f.rpm, 6800)
        let d = try DryingSessionInfo.decode(hex(g.dryingSession))
        XCTAssertEqual(d.sessionId, 42)
        XCTAssertEqual(d.material, .paCf)
        XCTAssertEqual(d.durationSeconds, 28800)
        XCTAssertEqual(d.elapsedDryingSeconds, 19140)
        XCTAssertEqual(d.startDate, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(try TargetTemperatureReading.decode(hex(g.targetTemp)), 70.0)
        XCTAssertEqual(try RemainingTimeReading.decode(hex(g.remainingTime)), 9660)
    }

    func testDecodeDeviceInfo() throws {
        let i = try DeviceInfo.decode(hex(golden().deviceInfo))
        XCTAssertEqual(i.protocolVersion, 1)
        XCTAssertEqual(i.hardwareRevision, 1)
        XCTAssertEqual(i.deviceId.hexString, "404cca12a1b2")
        XCTAssertEqual(i.firmwareVersion, "1.0.0")
        XCTAssertEqual(i.minTargetCelsius, 35)
        XCTAssertEqual(i.maxTargetCelsius, 70)
        XCTAssertEqual(i.maxDurationSeconds, 172_800)
        XCTAssertEqual(i.capabilities, [.heaterNtc, .fanTach, .safetyRelay, .identifyLed, .localButton])
        XCTAssertFalse(i.capabilities.contains(.otaBle))
        XCTAssertEqual(i.resetCause, .powerOn)
        XCTAssertEqual(i.shortId, "A1B2")
        XCTAssertTrue(i.isProtocolSupported)
    }

    func testCommandFramesMatchFirmwareBytes() throws {
        let c = try golden().commands
        let start = DeviceCommand.startSession(material: .paCf, targetCelsius: 70, durationSeconds: 28800,
                                               now: Date(timeIntervalSince1970: 1_790_000_000), fanMode: .auto)
        XCTAssertEqual(try start.frame(sequence: 1).hexString, c["startSession"])
        XCTAssertEqual(try DeviceCommand.stopSession.frame(sequence: 2).hexString, c["stopSession"])
        XCTAssertEqual(try DeviceCommand.setTargetTemperature(celsius: 45).frame(sequence: 3).hexString, c["setTargetTemp4500"])
        XCTAssertEqual(try DeviceCommand.setDuration(seconds: 3600).frame(sequence: 4).hexString, c["setDuration3600"])
        XCTAssertEqual(try DeviceCommand.setFilament(.petg).frame(sequence: 5).hexString, c["setFilamentPetg"])
        XCTAssertEqual(try DeviceCommand.setFanMode(.on).frame(sequence: 6).hexString, c["setFanModeOn"])
        XCTAssertEqual(try DeviceCommand.requestStatus.frame(sequence: 7).hexString, c["requestStatus"])
        XCTAssertEqual(try DeviceCommand.resetSession.frame(sequence: 8).hexString, c["resetSession"])
        XCTAssertEqual(try DeviceCommand.identify.frame(sequence: 9).hexString, c["identify"])
        XCTAssertEqual(try DeviceCommand.setDeviceName("Lab Dryer").frame(sequence: 10).hexString, c["setDeviceNameLabDryer"])
    }

    func testCommandValidation() {
        XCTAssertThrowsError(try DeviceCommand.setTargetTemperature(celsius: 90).payload())
        XCTAssertThrowsError(try DeviceCommand.setTargetTemperature(celsius: 20).payload())
        XCTAssertThrowsError(try DeviceCommand.setDuration(seconds: 60).payload())
        XCTAssertThrowsError(try DeviceCommand.setDuration(seconds: 200_000).payload())
        XCTAssertThrowsError(try DeviceCommand.setDeviceName("").payload())
        XCTAssertThrowsError(try DeviceCommand.setDeviceName(String(repeating: "x", count: 21)).payload())
        XCTAssertNoThrow(try DeviceCommand.setTargetTemperature(celsius: 70).payload())
    }

    func testDecodeResponses() throws {
        let g = try golden()
        let ack = try CommandResponse.decode(hex(g.responseStartAck))
        XCTAssertTrue(ack.isAck)
        XCTAssertEqual(ack.sequence, 1)
        XCTAssertEqual(ack.opcodeRaw, Opcode.startSession.rawValue)
        XCTAssertEqual(ack.startAck?.sessionId, 42)
        XCTAssertEqual(ack.startAck?.deviceTime, Date(timeIntervalSince1970: 1_790_000_000))
        let nack = try CommandResponse.decode(hex(g.responseStartNackOverTemp))
        XCTAssertFalse(nack.isAck)
        XCTAssertEqual(nack.result, .notAllowedInState)
        XCTAssertEqual(nack.rejectionState?.state, .overTemperature)
        XCTAssertEqual(nack.rejectionState?.error, .overTempChamber)
    }

    func testTruncatedPayloadsThrow() {
        XCTAssertThrowsError(try DeviceStatus.decode(Data([1, 3, 0])))
        XCTAssertThrowsError(try DeviceInfo.decode(Data(repeating: 0, count: 22)))
        XCTAssertThrowsError(try CommandResponse.decode(Data([1, 0x80])))
        XCTAssertThrowsError(try TemperatureReading.decode(Data([0x10])))
    }

    func testFutureProtocolAppendsAreIgnored() throws {
        var bytes = try hex(golden().deviceStatus)
        bytes.append(contentsOf: [0xAA, 0xBB, 0xCC])  // v1.x may append fields
        XCTAssertEqual(try DeviceStatus.decode(bytes).sessionId, 42)
    }

    func testUnknownStateThrows() throws {
        var bytes = [UInt8](try hex(golden().deviceStatus))
        bytes[1] = 77
        XCTAssertThrowsError(try DeviceStatus.decode(Data(bytes)))
    }

    func testUUIDsAreDocumentedValues() {
        XCTAssertEqual(SpoolDryProtocol.serviceUUID, "5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44")
        XCTAssertEqual(SpoolDryCharacteristic.deviceStatus.rawValue, "5D0F000A-2B7E-4C8A-9B1E-53504F4F4C44")
        XCTAssertEqual(SpoolDryCharacteristic.command.rawValue, "5D0F000B-2B7E-4C8A-9B1E-53504F4F4C44")
        XCTAssertEqual(Set(SpoolDryCharacteristic.allCases.map(\.rawValue)).count, SpoolDryCharacteristic.allCases.count)
    }
}
