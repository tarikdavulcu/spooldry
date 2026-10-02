import SpoolDryKit
import SwiftData
import XCTest
@testable import SpoolDry

/// App-level integration tests: the real SessionCoordinator + SwiftData (in memory) talking to a dryer
/// whose transport is the protocol-accurate simulated device (DemoDevice) but which is treated as a real,
/// non-demo dryer so the free-tier rules apply.
@MainActor
final class AppLogicTests: XCTestCase {
    private func makeCoordinator(used: Int = 0) -> (SessionCoordinator, InMemoryUsageCounterStore, ModelContainer) {
        let container = PersistenceController.makeContainer(inMemory: true)
        let usage = InMemoryUsageCounterStore(used)
        let coordinator = SessionCoordinator(context: container.mainContext, store: StoreManager(), usageStore: usage)
        return (coordinator, usage, container)
    }

    private func makeLink() -> DeviceLink {
        let link = DeviceLink(id: UUID(), name: "Test Dryer", isDemo: false)
        let device = DemoDevice()
        device.link = link
        link.demo = device
        link.info = device.info
        link.linkState = .connected
        device.start()
        return link
    }

    private var plan: DryingPlan {
        DryingPlan(material: .petg, filamentName: "PETG", targetCelsius: 65, durationSeconds: 3600, humidityTargetPercent: 20)
    }

    func testThreeFreeSessionsThenPaywall() async throws {
        let (coordinator, usage, _) = makeCoordinator()
        let link = makeLink()
        link.onStatus = { l, s in coordinator.handleStatus(s, from: l) }
        for i in 1...3 {
            try await coordinator.start(plan: plan, on: link)
            XCTAssertEqual(usage.load(), i)
            try await coordinator.stop(on: link)
            try await coordinator.reset(on: link)  // demo transport completes cooldown immediately when cool
        }
        XCTAssertEqual(coordinator.remainingFreeSessions, 0)
        do {
            try await coordinator.start(plan: plan, on: link)
            XCTFail("4th session must require the Lifetime purchase")
        } catch SessionCoordinator.StartError.paywallRequired {
            // expected
        }
        XCTAssertEqual(usage.load(), 3)
    }

    func testRejectedStartDoesNotConsumeASession() async throws {
        let (coordinator, usage, _) = makeCoordinator()
        let link = makeLink()
        try await coordinator.start(plan: plan, on: link)
        XCTAssertEqual(usage.load(), 1)
        do {
            try await coordinator.start(plan: plan, on: link)  // dryer is busy -> NACK BUSY
            XCTFail("Expected NACK")
        } catch let DeviceCommandError.rejected(code, _, _) {
            XCTAssertEqual(code, .busy)
        }
        XCTAssertEqual(usage.load(), 1)
    }

    func testDemoSessionsAreFree() async throws {
        let (coordinator, usage, _) = makeCoordinator(used: 3)
        let link = DeviceLink(id: DemoDevice.deviceID, name: "Demo", isDemo: true)
        let device = DemoDevice()
        device.link = link
        link.demo = device
        link.info = device.info
        link.linkState = .connected
        device.start()
        XCTAssertEqual(coordinator.decision(for: link), .allowed(remainingAfterStart: nil))
        try await coordinator.start(plan: plan, on: link)
        XCTAssertEqual(usage.load(), 3)
    }

    func testSessionRecordIsCreatedAndCompleted() async throws {
        let (coordinator, _, container) = makeCoordinator()
        let link = makeLink()
        link.onStatus = { l, s in coordinator.handleStatus(s, from: l) }
        try await coordinator.start(plan: plan, on: link)
        let records = try container.mainContext.fetch(FetchDescriptor<DryingSessionRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.outcome, .inProgress)
        // Feed a terminal status for this session.
        let sid = UInt32(records[0].deviceSessionId)
        let done = DeviceStatus(state: .completed, chamberCelsius: 44, humidityPercent: 12, targetCelsius: 65, remainingSeconds: 0,
                                elapsedDryingSeconds: 3600, sessionId: sid, endReason: .completed)
        coordinator.handleStatus(done, from: link)
        XCTAssertEqual(records.first?.outcome, .completed)
        XCTAssertEqual(records.first?.elapsedDryingSeconds, 3600)
    }

    func testCommandsFailWhenDisconnected() async {
        let link = DeviceLink(id: UUID(), name: "Offline")
        do {
            try await link.send(.requestStatus)
            XCTFail("Expected notConnected")
        } catch {
            XCTAssertEqual(error as? DeviceCommandError, .notConnected)
        }
    }

    func testLiveActivityContentStateCodable() throws {
        let display = DryingDisplayState(state: .drying, chamberCelsius: 67, humidityPercent: 18, targetCelsius: 70,
                                         dryingEndDate: Date(timeIntervalSince1970: 1_790_009_660), remainingSeconds: 9660,
                                         durationSeconds: 28800, progress: 0.66, updatedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let state = SpoolDryActivityAttributes.ContentState(display: display, isConnected: true)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SpoolDryActivityAttributes.ContentState.self, from: data), state)
    }

    func testAllSixLanguagesAreBundled() {
        let localizations = Set(Bundle.main.localizations)
        for code in ["en", "de", "fr", "es", "ar", "ja"] {
            XCTAssertTrue(localizations.contains(code), "missing localization \(code)")
        }
    }
}
