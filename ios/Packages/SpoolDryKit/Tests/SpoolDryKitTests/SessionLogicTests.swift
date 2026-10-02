import XCTest
@testable import SpoolDryKit

final class FreeTierTests: XCTestCase {
    func testExactlyThreeFreeSessions() {
        let p = FreeTierPolicy()
        XCTAssertEqual(p.decision(hasLifetime: false, usedSessions: 0), .allowed(remainingAfterStart: 2))
        XCTAssertEqual(p.decision(hasLifetime: false, usedSessions: 1), .allowed(remainingAfterStart: 1))
        XCTAssertEqual(p.decision(hasLifetime: false, usedSessions: 2), .allowed(remainingAfterStart: 0))  // 3rd session
        XCTAssertEqual(p.decision(hasLifetime: false, usedSessions: 3), .paywall)                          // 4th -> paywall
        XCTAssertEqual(p.decision(hasLifetime: false, usedSessions: 50), .paywall)
        XCTAssertEqual(p.remainingFreeSessions(usedSessions: 3), 0)
        XCTAssertEqual(p.remainingFreeSessions(usedSessions: -2), 3)
    }

    func testLifetimeIsUnlimited() {
        XCTAssertEqual(FreeTierPolicy().decision(hasLifetime: true, usedSessions: 999), .allowed(remainingAfterStart: nil))
    }

    func testLedgerCountsEachDeviceSessionOnce() {
        let store = InMemoryUsageCounterStore()
        let ledger = FreeSessionLedger(store: store)
        XCTAssertEqual(ledger.recordStartedSession(sessionKey: "A1B2:1"), 1)
        XCTAssertEqual(ledger.recordStartedSession(sessionKey: "A1B2:1"), 1)  // duplicate ACK
        XCTAssertEqual(ledger.recordStartedSession(sessionKey: "A1B2:2"), 2)
        XCTAssertEqual(ledger.recordStartedSession(sessionKey: "C3D4:1"), 3)
        XCTAssertEqual(store.load(), 3)
        XCTAssertEqual(FreeTierPolicy().decision(hasLifetime: false, usedSessions: ledger.used), .paywall)
    }

    func testCounterSurvivesNewLedgerInstance() {
        let store = InMemoryUsageCounterStore(2)
        let ledger = FreeSessionLedger(store: store)  // e.g. app relaunch / phone restart
        XCTAssertEqual(ledger.used, 2)
        ledger.recordStartedSession(sessionKey: "X:9")
        XCTAssertEqual(FreeSessionLedger(store: store).used, 3)
    }
}

final class SessionTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func status(_ state: DeviceState, sid: UInt32 = 7, c: Double? = 50, h: Double? = 40, rem: UInt32? = 3600,
                        elapsed: UInt32 = 0, end: SessionEndReason = .none, err: DeviceErrorCode = .none) -> DeviceStatus {
        DeviceStatus(state: state, error: err, chamberCelsius: c, humidityPercent: h, targetCelsius: 50, remainingSeconds: rem,
                     elapsedDryingSeconds: elapsed, sessionId: sid, endReason: end)
    }

    func testCompletedSessionSummary() {
        var t = SessionTracker(deviceSessionId: 7, startedAt: t0, durationSeconds: 3600)
        t.ingest(status(.preheating, c: 25, h: 45), at: t0)
        t.ingest(status(.drying, c: 49, h: 30, rem: 3600, elapsed: 0), at: t0.addingTimeInterval(900))
        t.ingest(status(.drying, c: 51, h: 18, rem: 1800, elapsed: 1800), at: t0.addingTimeInterval(2700))
        t.ingest(status(.cooldown, c: 47, h: 15, rem: 0, elapsed: 3600, end: .completed), at: t0.addingTimeInterval(4500))
        XCTAssertFalse(t.isFinished)
        XCTAssertTrue(t.ingest(status(.completed, c: 44, h: 16, rem: 0, elapsed: 3600, end: .completed), at: t0.addingTimeInterval(4800)))
        let s = t.summary
        XCTAssertEqual(s.outcome, .completed)
        XCTAssertEqual(s.startHumidity, 45)
        XCTAssertEqual(s.endHumidity, 16)
        XCTAssertEqual(s.minHumidity, 15)
        XCTAssertEqual(try XCTUnwrap(s.averageDryingTemperature), 50, accuracy: 0.001)
        XCTAssertEqual(s.maxTemperature, 51)
        XCTAssertEqual(s.elapsedDryingSeconds, 3600)
        XCTAssertEqual(s.dryingStartedAt, t0.addingTimeInterval(900))
        XCTAssertEqual(s.humidityReduction, 29)
        XCTAssertFalse(t.ingest(status(.idle), at: t0.addingTimeInterval(9000)))  // finished sessions ignore updates
    }

    func testStoppedFailedOverTempDisconnected() {
        var a = SessionTracker(deviceSessionId: 7, startedAt: t0, durationSeconds: 3600)
        a.ingest(status(.idle, rem: nil, elapsed: 600, end: .stoppedByUser), at: t0)
        XCTAssertEqual(a.summary.outcome, .stopped)

        var b = SessionTracker(deviceSessionId: 7, startedAt: t0, durationSeconds: 3600)
        b.ingest(status(.error, rem: nil, err: .fanFailure), at: t0)
        XCTAssertEqual(b.summary.outcome, .failed)
        XCTAssertEqual(b.summary.errorCode, .fanFailure)

        var c = SessionTracker(deviceSessionId: 7, startedAt: t0, durationSeconds: 3600)
        c.ingest(status(.overTemperature, rem: nil, end: .overTemperature, err: .overTempChamber), at: t0)
        XCTAssertEqual(c.summary.outcome, .overTemperature)

        var d = SessionTracker(deviceSessionId: 7, startedAt: t0, durationSeconds: 3600)
        d.markDisconnected(at: t0)
        XCTAssertEqual(d.summary.outcome, .disconnected)
    }

    func testDeviceRebootFailsSession() {
        var t = SessionTracker(deviceSessionId: 7, startedAt: t0, durationSeconds: 3600)
        t.ingest(status(.drying), at: t0)
        // After an ESP32 reset the device is idle with session 0 and reports UNEXPECTED_RESET.
        t.ingest(status(.idle, sid: 0, rem: nil, err: .unexpectedReset), at: t0.addingTimeInterval(60))
        XCTAssertEqual(t.summary.outcome, .failed)
        XCTAssertEqual(t.summary.errorCode, .unexpectedReset)
    }

    func testResetAfterFullDurationCountsAsCompleted() {
        var t = SessionTracker(deviceSessionId: 7, startedAt: t0, durationSeconds: 3600)
        t.ingest(status(.idle, rem: nil, elapsed: 3600, end: .none), at: t0)
        XCTAssertEqual(t.summary.outcome, .completed)
    }

    func testSamplesAreDownsampled() {
        var t = SessionTracker(deviceSessionId: 7, startedAt: t0, durationSeconds: 36_000)
        for i in 0..<3600 {  // one status per second for an hour
            t.ingest(status(.drying, elapsed: UInt32(i)), at: t0.addingTimeInterval(TimeInterval(i)))
        }
        XCTAssertEqual(t.summary.samples.count, 12)  // every 5 minutes
    }
}

final class DisplayStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testPreheatingHasNoCountdownOrProgress() {
        let s = DeviceStatus(state: .preheating, chamberCelsius: 40, humidityPercent: 30, targetCelsius: 70, remainingSeconds: 28800)
        let d = DryingDisplayState.from(status: s, durationSeconds: 28800, receivedAt: now)
        XCTAssertNil(d.dryingEndDate)
        XCTAssertNil(d.progress)
        XCTAssertEqual(d.remaining(at: now), 28800)
    }

    func testDryingCountdownDerivedFromDevice() {
        let s = DeviceStatus(state: .drying, chamberCelsius: 67, humidityPercent: 18, targetCelsius: 70, remainingSeconds: 9660, elapsedDryingSeconds: 19140)
        let d = DryingDisplayState.from(status: s, durationSeconds: 28800, receivedAt: now)
        XCTAssertEqual(d.dryingEndDate, now.addingTimeInterval(9660))
        XCTAssertEqual(try XCTUnwrap(d.progress), 19140.0 / 28800.0, accuracy: 0.0001)
        XCTAssertEqual(d.remaining(at: now.addingTimeInterval(60)), 9600)
        XCTAssertFalse(d.isStale(at: now.addingTimeInterval(60)))
        XCTAssertTrue(d.isStale(at: now.addingTimeInterval(600)))
    }

    func testCompletedIsFullProgress() {
        let s = DeviceStatus(state: .completed, chamberCelsius: 44, humidityPercent: 12, targetCelsius: 70, remainingSeconds: 0, elapsedDryingSeconds: 28800, endReason: .completed)
        let d = DryingDisplayState.from(status: s, durationSeconds: 28800, receivedAt: now)
        XCTAssertEqual(d.progress, 1)
        XCTAssertTrue(d.isTerminal)
    }

    func testErrorStateHasNoProgress() {
        let s = DeviceStatus(state: .error, error: .sensorI2c, chamberCelsius: nil, humidityPercent: nil, targetCelsius: 70, remainingSeconds: nil)
        let d = DryingDisplayState.from(status: s, durationSeconds: 28800, receivedAt: now)
        XCTAssertNil(d.progress)
        XCTAssertNil(d.remaining(at: now))
        XCTAssertEqual(d.errorCode, .sensorI2c)
    }
}

final class FilamentDatabaseTests: XCTestCase {
    func testAllRequiredMaterialsPresent() {
        let required: [MaterialCode] = [.pla, .petg, .abs, .asa, .tpu, .pa, .pc, .pva, .bvoh, .peek, .pei, .pps, .paCf, .paGf, .petgCf, .plaCf, .pcCf]
        for m in required { XCTAssertNotNil(FilamentDatabase.guidance(for: m), "missing \(m)") }
        XCTAssertNil(FilamentDatabase.guidance(for: .custom))
    }

    func testEveryEntryIsSourcedAndWithinDeviceLimits() {
        for g in FilamentDatabase.all {
            XCTAssertFalse(g.references.isEmpty, "\(g.displayName) has no manufacturer reference")
            for r in g.references { XCTAssertEqual(r.url.scheme, "https") }
            XCTAssertLessThanOrEqual(g.suggestedCelsius, FilamentDatabase.deviceMaxCelsius)
            XCTAssertGreaterThanOrEqual(g.suggestedCelsius, FilamentDatabase.deviceMinCelsius)
            XCTAssertGreaterThan(g.suggestedHours, 0)
            XCTAssertTrue((1...60).contains(g.humidityTargetPercent))
            XCTAssertTrue(FilamentProfile.builtIn(g).validate().isEmpty, "\(g.displayName) built-in profile invalid")
        }
    }

    func testHighTemperaturePolymersAreFlagged() {
        for m: MaterialCode in [.peek, .pei, .pps, .ppsCf] {
            let g = try! XCTUnwrap(FilamentDatabase.guidance(for: m))
            XCTAssertTrue(g.exceedsDeviceLimit)
            XCTAssertTrue(g.warningKeys.contains("warning.highTempDryerRequired"))
        }
        XCTAssertFalse(FilamentDatabase.guidance(for: .pla)!.exceedsDeviceLimit)
    }

    func testBuiltInProfileIdsAreStable() {
        XCTAssertEqual(FilamentProfile.builtIn(FilamentDatabase.guidance(for: .pla)!).id,
                       FilamentProfile.builtIn(FilamentDatabase.guidance(for: .pla)!).id)
        XCTAssertEqual(Set(FilamentProfile.builtIns.map(\.id)).count, FilamentProfile.builtIns.count)
    }

    func testCustomProfileValidationAndPlanClamping() {
        var p = FilamentProfile(brand: "Acme", material: .paCf, name: "PA-CF", temperature: 85, duration: 8 * 3600,
                                humidityTarget: 15, source: .user(reference: nil))
        XCTAssertEqual(p.validate(), [.temperatureAboveDeviceMax(70)])
        let plan = DryingPlan(profile: p)
        XCTAssertEqual(plan.targetCelsius, 70)
        XCTAssertEqual(plan.durationSeconds, 28800)
        XCTAssertEqual(plan.compactLabel, "PA-CF")
        p.name = " "
        p.temperature = 30
        p.duration = 60
        XCTAssertEqual(Set(p.validate().map { "\($0)" }).count, 3)
    }
}

final class StatisticsAndFormattingTests: XCTestCase {
    func testStatistics() {
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        let s = DryingStatistics.compute([
            SessionStatInput(material: .pla, filamentName: "PLA", startedAt: d, dryingSeconds: 7200, outcome: .completed, startHumidity: 40, endHumidity: 15),
            SessionStatInput(material: .paCf, filamentName: "PA-CF", startedAt: d.addingTimeInterval(100), dryingSeconds: 3600, outcome: .stopped, startHumidity: 35, endHumidity: 20),
            SessionStatInput(material: .pla, filamentName: "PLA", startedAt: d.addingTimeInterval(200), dryingSeconds: 3600, outcome: .completed, startHumidity: nil, endHumidity: 10),
            SessionStatInput(material: .petg, filamentName: "PETG", startedAt: d.addingTimeInterval(300), dryingSeconds: 0, outcome: .inProgress, startHumidity: 50, endHumidity: nil),
        ])
        XCTAssertEqual(s.totalSessions, 3)
        XCTAssertEqual(s.completedSessions, 2)
        XCTAssertEqual(s.totalDryingHours, 4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(s.averageHumidityReduction), 20, accuracy: 0.0001)
        XCTAssertEqual(s.mostUsedMaterial, .pla)
        XCTAssertEqual(s.lastSessionDate, d.addingTimeInterval(200))
    }

    func testFormatting() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(SpoolDryFormat.temperature(48.2, unit: .celsius, locale: en), "48.2°C")
        XCTAssertEqual(SpoolDryFormat.temperature(100, unit: .fahrenheit, locale: en), "212.0°F")
        XCTAssertEqual(SpoolDryFormat.temperature(nil, unit: .celsius), "--")
        XCTAssertEqual(SpoolDryFormat.hoursMinutes(9660), "02:41")
        XCTAssertEqual(SpoolDryFormat.hoursMinutes(59), "00:01")
        XCTAssertEqual(SpoolDryFormat.humidity(18.4, locale: en), "18%")
        let de = Locale(identifier: "de_DE")
        XCTAssertEqual(SpoolDryFormat.temperature(48.2, unit: .celsius, locale: de), "48,2°C")
        XCTAssertEqual(TemperatureUnit.fahrenheit.toCelsius(212), 100, accuracy: 0.0001)
    }
}
