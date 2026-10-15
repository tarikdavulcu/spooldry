import XCTest
@testable import SpoolDryKit

final class BTHomeParserTests: XCTestCase {
    func testSpecExampleTemperatureAndHumidity() throws {
        // bthome.io example: device info 0x40, temperature 25.06 °C, humidity 50.55 %
        let r = try XCTUnwrap(BTHomeParser.parse(Data([0x40, 0x02, 0xCA, 0x09, 0x03, 0xBF, 0x13])))
        XCTAssertEqual(try XCTUnwrap(r.temperatureCelsius), 25.06, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(r.humidityPercent), 50.55, accuracy: 0.0001)
        XCTAssertFalse(r.isEncrypted)
        XCTAssertTrue(r.hasHumidity)
    }

    func testPacketIdBatteryAndNegativeTemperature() throws {
        // packet id 7, battery 88 %, temperature -5.25 °C (0xFDF3), humidity 12 % as uint8 (0x2E)
        let r = try XCTUnwrap(BTHomeParser.parse(Data([0x40, 0x00, 0x07, 0x01, 0x58, 0x02, 0xF3, 0xFD, 0x2E, 0x0C])))
        XCTAssertEqual(r.packetID, 7)
        XCTAssertEqual(r.batteryPercent, 88)
        XCTAssertEqual(try XCTUnwrap(r.temperatureCelsius), -5.25, accuracy: 0.0001)
        XCTAssertEqual(r.humidityPercent, 12)
    }

    func testSkipsOtherObjectsAndStopsAtUnknown() throws {
        // pressure (0x04, 3 bytes) is skipped, humidity read, then unknown 0xEE stops parsing safely
        let r = try XCTUnwrap(BTHomeParser.parse(Data([0x40, 0x04, 0x13, 0x8A, 0x01, 0x03, 0xD0, 0x07, 0xEE, 0x01, 0x02])))
        XCTAssertEqual(try XCTUnwrap(r.humidityPercent), 20.0, accuracy: 0.0001)
        XCTAssertNil(r.temperatureCelsius)
    }

    func testEncryptedAndWrongVersion() throws {
        let enc = try XCTUnwrap(BTHomeParser.parse(Data([0x41, 0x01, 0x02, 0x03])))
        XCTAssertTrue(enc.isEncrypted)
        XCTAssertNil(enc.humidityPercent)
        XCTAssertNil(BTHomeParser.parse(Data([0x20, 0x03, 0x00, 0x10])))   // BTHome v1 header
        XCTAssertNil(BTHomeParser.parse(Data()))
    }

    func testTruncatedPayloadDoesNotCrash() throws {
        let r = try XCTUnwrap(BTHomeParser.parse(Data([0x40, 0x02, 0xCA])))
        XCTAssertNil(r.temperatureCelsius)
    }
}

final class StorageAdvisorTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testHoursAboveIntegratesAndCapsGaps() {
        let samples = [
            HumiditySample(t: t0, h: 15),
            HumiditySample(t: t0.addingTimeInterval(3600), h: 30),         // above for 1 h until next sample
            HumiditySample(t: t0.addingTimeInterval(7200), h: 18),
            HumiditySample(t: t0.addingTimeInterval(10 * 3600), h: 35),    // last sample: counted up to the 2 h gap cap
        ]
        let hours = StorageAdvisor.hoursAbove(limit: 20, samples: samples, since: t0, now: t0.addingTimeInterval(20 * 3600))
        XCTAssertEqual(hours, 3, accuracy: 0.0001)
    }

    func testHoursAboveIgnoresTimeBeforeLastDrying() {
        let samples = [HumiditySample(t: t0, h: 40), HumiditySample(t: t0.addingTimeInterval(3600), h: 40)]
        let hours = StorageAdvisor.hoursAbove(limit: 20, samples: samples, since: t0.addingTimeInterval(1800),
                                              now: t0.addingTimeInterval(5400))
        XCTAssertEqual(hours, 1, accuracy: 0.0001)
    }

    func testConditionInBox() {
        let humid = (0..<12).map { HumiditySample(t: t0.addingTimeInterval(Double($0) * 3600), h: 35) }
        let now = t0.addingTimeInterval(12 * 3600)
        XCTAssertEqual(StorageAdvisor.conditionInBox(sensitivity: .veryHigh, humidityTarget: 20, lastDried: t0,
                                                     samples: humid, now: now), .needsDrying)
        XCTAssertEqual(StorageAdvisor.conditionInBox(sensitivity: .moderate, humidityTarget: 20, lastDried: t0,
                                                     samples: humid, now: now), .watch)
        XCTAssertEqual(StorageAdvisor.conditionInBox(sensitivity: .low, humidityTarget: 40, lastDried: t0,
                                                     samples: humid, now: now), .dry)
        XCTAssertEqual(StorageAdvisor.conditionInBox(sensitivity: .low, humidityTarget: 40, lastDried: nil,
                                                     samples: humid, now: now), .unknown)
    }

    func testConditionInOpenAir() {
        let now = t0.addingTimeInterval(3 * 86400)
        XCTAssertEqual(StorageAdvisor.conditionInOpenAir(sensitivity: .high, lastDried: t0, now: now), .needsDrying)
        XCTAssertEqual(StorageAdvisor.conditionInOpenAir(sensitivity: .moderate, lastDried: t0, now: now), .dry)
        XCTAssertEqual(StorageAdvisor.conditionInOpenAir(sensitivity: .moderate, lastDried: t0,
                                                         now: t0.addingTimeInterval(4 * 86400)), .watch)
    }

    func testCompactKeepsLatestPerBucketAndDropsOld() {
        let now = t0.addingTimeInterval(20 * 86400)
        let samples = [
            HumiditySample(t: t0, h: 50),                                   // older than 14 days -> dropped
            HumiditySample(t: now.addingTimeInterval(-100), h: 10),
            HumiditySample(t: now.addingTimeInterval(-50), h: 11),          // same 10-minute bucket, newer
        ]
        let out = StorageAdvisor.compact(samples, now: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.h, 11)
    }
}
