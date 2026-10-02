import ActivityKit
import Foundation
import SpoolDryKit

/// Starts, updates and ends the drying Live Activity. Content always mirrors the last device report;
/// a stale date marks the activity as outdated when no update arrived for 15 minutes.
@MainActor
final class LiveActivityManager {
    private var lastPush: [String: (state: DeviceState, at: Date, temp: Double?, rh: Double?)] = [:]

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private func activity(deviceID: UUID, sessionId: UInt32) -> Activity<SpoolDryActivityAttributes>? {
        Activity<SpoolDryActivityAttributes>.activities.first {
            $0.attributes.deviceID == deviceID.uuidString && $0.attributes.deviceSessionId == sessionId
        }
    }

    func start(attributes: SpoolDryActivityAttributes, state: SpoolDryActivityAttributes.ContentState) {
        guard areActivitiesEnabled else { return }
        if let existing = activity(deviceID: UUID(uuidString: attributes.deviceID) ?? UUID(), sessionId: attributes.deviceSessionId) {
            Task { await existing.update(content(state)) }
            return
        }
        do {
            _ = try Activity.request(attributes: attributes, content: content(state), pushType: nil)
        } catch {
            // Live Activities can be disabled per app or budget-limited; the app works without them.
        }
    }

    /// Updates on state changes immediately, otherwise at most every 30 s when values moved noticeably.
    func update(deviceID: UUID, sessionId: UInt32, state: SpoolDryActivityAttributes.ContentState) {
        guard let a = activity(deviceID: deviceID, sessionId: sessionId) else { return }
        let key = a.id
        let now = Date()
        if let last = lastPush[key] {
            let stateChanged = last.state != state.display.state
            let tempMoved = abs((last.temp ?? 0) - (state.display.chamberCelsius ?? 0)) >= 0.5
            let rhMoved = abs((last.rh ?? 0) - (state.display.humidityPercent ?? 0)) >= 1
            let elapsed = now.timeIntervalSince(last.at)
            guard stateChanged || (elapsed >= 30 && (tempMoved || rhMoved)) || elapsed >= 300 else { return }
        }
        lastPush[key] = (state.display.state, now, state.display.chamberCelsius, state.display.humidityPercent)
        Task { await a.update(content(state)) }
    }

    func end(deviceID: UUID, sessionId: UInt32, finalState: SpoolDryActivityAttributes.ContentState) {
        guard let a = activity(deviceID: deviceID, sessionId: sessionId) else { return }
        lastPush[a.id] = nil
        Task {
            await a.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(4 * 3600)))
        }
    }

    func endAll() {
        for a in Activity<SpoolDryActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func content(_ state: SpoolDryActivityAttributes.ContentState) -> ActivityContent<SpoolDryActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60), relevanceScore: state.display.state == .drying ? 80 : 60)
    }
}
