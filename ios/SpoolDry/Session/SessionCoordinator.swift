import Foundation
import Observation
import SpoolDryKit
import SwiftData
import WidgetKit

/// Orchestrates drying sessions: free-tier gate, START/ACK handshake, history records,
/// Live Activities, widgets and notifications. All values shown come from the device.
@MainActor
@Observable
final class SessionCoordinator {
    enum StartError: LocalizedError {
        case paywallRequired
        case notReady
        case missingAck

        var errorDescription: String? {
            switch self {
            case .paywallRequired: return String(localized: "You have used your 3 free drying sessions.")
            case .notReady: return String(localized: "Connect to your dryer first.")
            case .missingAck: return String(localized: "The dryer did not return a session ID.")
            }
        }
    }

    struct LivePoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let celsius: Double?
        let humidity: Double?
    }

    private struct ActiveSession {
        var recordID: UUID
        var tracker: SessionTracker
        var plan: DryingPlan
        var deviceName: String
        var baseSamples: [SessionSample]
        var lastPersistedSampleCount: Int
        var lastState: DeviceState
    }

    let store: StoreManager
    let policy = FreeTierPolicy()
    private(set) var usedFreeSessions: Int
    private(set) var liveSeries: [UUID: [LivePoint]] = [:]

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let ledger: FreeSessionLedger
    @ObservationIgnored private let liveActivities = LiveActivityManager()
    @ObservationIgnored private let notifications = NotificationManager()
    @ObservationIgnored private var active: [UUID: ActiveSession] = [:]
    @ObservationIgnored private var lastWidgetReload = Date.distantPast
    @ObservationIgnored private var lastWidgetState: DeviceState?
    @ObservationIgnored var activeDeviceIDProvider: () -> UUID? = { nil }

    init(context: ModelContext, store: StoreManager, usageStore: UsageCounterStore = KeychainUsageCounterStore()) {
        let ledger = FreeSessionLedger(store: usageStore)
        self.context = context
        self.store = store
        self.ledger = ledger
        self.usedFreeSessions = ledger.used
    }

    // MARK: Settings (shared with SettingsView via @AppStorage keys)

    var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.temperatureUnit) ?? "") ?? .preferred()
    }

    private var liveActivitiesEnabled: Bool {
        (UserDefaults.standard.object(forKey: SettingsKeys.liveActivities) as? Bool) ?? true
    }

    private var notificationsEnabled: Bool {
        (UserDefaults.standard.object(forKey: SettingsKeys.notifications) as? Bool) ?? true
    }

    // MARK: Free tier

    var remainingFreeSessions: Int { policy.remainingFreeSessions(usedSessions: usedFreeSessions) }

    func decision(for link: DeviceLink) -> FreeTierPolicy.Decision {
        if link.isDemo { return .allowed(remainingAfterStart: nil) }  // demo bakes are not real sessions
        return policy.decision(hasLifetime: store.hasLifetime, usedSessions: usedFreeSessions)
    }

    func hasActiveSession(on id: UUID) -> Bool { active[id] != nil }

    // MARK: Commands

    func start(plan: DryingPlan, on link: DeviceLink) async throws {
        guard link.isReady else { throw StartError.notReady }
        if case .paywall = decision(for: link) { throw StartError.paywallRequired }
        // Ask for notification permission without blocking the start command on the system alert.
        if notificationsEnabled { Task { await notifications.requestAuthorizationIfNeeded() } }

        // The session only exists once the dryer acknowledges it.
        let response = try await link.send(plan.command)
        guard let ack = response.startAck else { throw StartError.missingAck }
        let now = Date()

        if !link.isDemo {
            let key = "\(link.info?.deviceId.hexString ?? link.id.uuidString):\(ack.sessionId)"
            usedFreeSessions = ledger.recordStartedSession(sessionKey: key)
        }

        let record = DryingSessionRecord(plan: plan, deviceSessionId: ack.sessionId, deviceID: link.id,
                                         deviceName: link.name, isDemo: link.isDemo, startedAt: now)
        context.insert(record)
        try? context.save()

        let tracker = SessionTracker(deviceSessionId: ack.sessionId, startedAt: now, durationSeconds: plan.durationSeconds)
        active[link.id] = ActiveSession(recordID: record.id, tracker: tracker, plan: plan, deviceName: link.name,
                                        baseSamples: [], lastPersistedSampleCount: 0, lastState: .preheating)

        if liveActivitiesEnabled {
            let attributes = SpoolDryActivityAttributes(filamentLabel: plan.compactLabel, materialRaw: plan.material.rawValue,
                                                        deviceName: link.name, deviceID: link.id.uuidString,
                                                        deviceSessionId: ack.sessionId,
                                                        temperatureUnitRaw: temperatureUnit.rawValue)
            let display = link.status.map { DryingDisplayState.from(status: $0, durationSeconds: plan.durationSeconds, receivedAt: now) }
                ?? DryingDisplayState(state: .preheating, chamberCelsius: nil, humidityPercent: nil, targetCelsius: plan.targetCelsius,
                                      dryingEndDate: nil, remainingSeconds: plan.durationSeconds, durationSeconds: plan.durationSeconds,
                                      progress: nil, updatedAt: now)
            var state = display
            state.state = .preheating
            liveActivities.start(attributes: attributes, state: .init(display: state, isConnected: true))
        }
        _ = try? await link.send(.requestStatus)
    }

    func stop(on link: DeviceLink) async throws {
        try await link.send(.stopSession)
    }

    func reset(on link: DeviceLink) async throws {
        try await link.send(.resetSession)
    }

    // MARK: Device updates

    func handleStatus(_ status: DeviceStatus, from link: DeviceLink) {
        let now = Date()
        appendLivePoint(status, for: link.id, at: now)

        guard var session = active[link.id] else {
            if link.id == activeDeviceIDProvider() {
                let duration = link.sessionInfo?.durationSeconds ?? status.remainingSeconds ?? 0
                writeWidget(link: link, label: status.isSessionActive ? status.material.shortName : nil,
                            display: .from(status: status, durationSeconds: duration, receivedAt: now))
            }
            return
        }

        let previousState = session.lastState
        session.tracker.ingest(status, at: now)
        session.lastState = status.state
        let display = DryingDisplayState.from(status: status, durationSeconds: session.plan.durationSeconds, receivedAt: now)

        if previousState == .preheating && status.state == .drying && notificationsEnabled {
            notifications.notifyDryingStarted(filament: session.plan.compactLabel)
        }

        let summary = session.tracker.summary
        if session.tracker.isFinished || summary.samples.count != session.lastPersistedSampleCount || previousState != status.state {
            persist(summary, into: session)
            session.lastPersistedSampleCount = summary.samples.count
        }

        if link.id == activeDeviceIDProvider() || active.count == 1 {
            writeWidget(link: link, label: session.plan.compactLabel, display: display)
        }

        if session.tracker.isFinished {
            liveActivities.end(deviceID: link.id, sessionId: session.tracker.summary.deviceSessionId,
                               finalState: .init(display: display, isConnected: true))
            if notificationsEnabled {
                notifications.notifyOutcome(summary.outcome, filament: session.plan.compactLabel,
                                            deviceName: session.deviceName, error: summary.errorCode)
            }
            active[link.id] = nil
        } else {
            liveActivities.update(deviceID: link.id, sessionId: summary.deviceSessionId,
                                  state: .init(display: display, isConnected: true))
            active[link.id] = session
        }
    }

    func handleLinkChange(_ link: DeviceLink) {
        guard let session = active[link.id], link.linkState != .connected else { return }
        // Keep the last known values but flag the connection loss; the dryer continues on its own.
        if let status = link.status {
            var display = DryingDisplayState.from(status: status, durationSeconds: session.plan.durationSeconds,
                                                  receivedAt: link.lastStatusAt ?? Date())
            display.updatedAt = link.lastStatusAt ?? display.updatedAt
            liveActivities.update(deviceID: link.id, sessionId: session.tracker.summary.deviceSessionId,
                                  state: .init(display: display, isConnected: false))
        }
    }

    /// Re-attaches trackers to sessions that were in progress when the app was terminated.
    func restoreInProgressSessions() {
        let inProgress = SessionOutcome.inProgress.rawValue
        let descriptor = FetchDescriptor<DryingSessionRecord>(predicate: #Predicate { $0.outcomeRaw == inProgress })
        guard let records = try? context.fetch(descriptor) else { return }
        let now = Date()
        for r in records {
            let plan = DryingPlan(material: r.material, filamentName: r.filamentName, brand: r.brand, profileID: r.profileID,
                                  targetCelsius: r.targetCelsius, durationSeconds: UInt32(clamping: r.durationSeconds),
                                  humidityTargetPercent: r.humidityTargetPercent)
            var tracker = SessionTracker(deviceSessionId: UInt32(clamping: r.deviceSessionId), startedAt: r.startedAt,
                                         durationSeconds: plan.durationSeconds)
            // Never seen again long after it should have ended -> outcome unknown ("Disconnected").
            let giveUp = r.startedAt.addingTimeInterval(TimeInterval(r.durationSeconds) + 52 * 3600)
            if now > giveUp {
                tracker.markDisconnected(at: now)
                r.outcomeRaw = SessionOutcome.disconnected.rawValue
                r.endedAt = now
                continue
            }
            active[r.devicePeripheralID] = ActiveSession(recordID: r.id, tracker: tracker, plan: plan, deviceName: r.deviceName,
                                                         baseSamples: r.samples, lastPersistedSampleCount: 0,
                                                         lastState: .disconnected)
        }
        try? context.save()
    }

    func refreshUsage() { usedFreeSessions = ledger.used }

    // MARK: Helpers

    private func persist(_ summary: SessionSummary, into session: ActiveSession) {
        let id = session.recordID
        let descriptor = FetchDescriptor<DryingSessionRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(descriptor).first else { return }
        let previousStart = record.startHumidity
        let previousMin = record.minHumidity
        let previousMax = record.maxTemperature
        record.apply(summary)
        if let previousStart { record.startHumidity = previousStart }
        if let previousMin { record.minHumidity = min(previousMin, record.minHumidity ?? previousMin) }
        if let previousMax { record.maxTemperature = max(previousMax, record.maxTemperature ?? previousMax) }
        if !session.baseSamples.isEmpty {
            let offset = record.startedAt.timeIntervalSince(summary.startedAt)
            let shifted = summary.samples.map { SessionSample(t: $0.t - offset, c: $0.c, h: $0.h) }
            record.samplesData = try? JSONEncoder().encode(session.baseSamples + shifted)
        }
        try? context.save()
    }

    private func appendLivePoint(_ s: DeviceStatus, for id: UUID, at now: Date) {
        var series = liveSeries[id] ?? []
        if let last = series.last, now.timeIntervalSince(last.date) < 15 { return }
        series.append(LivePoint(date: now, celsius: s.chamberCelsius, humidity: s.humidityPercent))
        let cutoff = now.addingTimeInterval(-3 * 3600)
        series.removeAll { $0.date < cutoff }
        liveSeries[id] = series
    }

    private func writeWidget(link: DeviceLink, label: String?, display: DryingDisplayState) {
        WidgetSnapshot(deviceName: link.name, filamentLabel: label, display: display,
                       isConnected: link.linkState == .connected, temperatureUnit: temperatureUnit).save()
        let now = Date()
        if lastWidgetState != display.state || now.timeIntervalSince(lastWidgetReload) > 300 {
            lastWidgetState = display.state
            lastWidgetReload = now
            WidgetCenter.shared.reloadTimelines(ofKind: SharedConstants.widgetKind)
        }
    }
}

enum SettingsKeys {
    static let temperatureUnit = "settings.temperatureUnit"
    static let liveActivities = "settings.liveActivities"
    static let notifications = "settings.notifications"
    static let onboardingDone = "settings.onboardingDone"
    static let activeDevice = "settings.activeDevice"
    static let retentionDays = "settings.retentionDays"
    static let demoEnabled = "settings.demoEnabled"
}
