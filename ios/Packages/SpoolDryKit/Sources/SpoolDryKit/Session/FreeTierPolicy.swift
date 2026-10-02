import Foundation

/// Product rule: the free version includes exactly 3 drying sessions. A session is *consumed* at the
/// moment the device acknowledges START_SESSION (ACK). Failed attempts, NACKs, timeouts, app launches,
/// days, timer views and device restarts never consume a session. The Lifetime purchase removes the limit.
public struct FreeTierPolicy: Equatable, Sendable {
    public static let freeSessionLimit = 3
    public let limit: Int

    public init(limit: Int = FreeTierPolicy.freeSessionLimit) { self.limit = limit }

    public enum Decision: Equatable, Sendable {
        case allowed(remainingAfterStart: Int?)  // nil = unlimited (Lifetime)
        case paywall
    }

    public func decision(hasLifetime: Bool, usedSessions: Int) -> Decision {
        if hasLifetime { return .allowed(remainingAfterStart: nil) }
        let used = max(0, usedSessions)
        guard used < limit else { return .paywall }
        return .allowed(remainingAfterStart: limit - used - 1)
    }

    public func remainingFreeSessions(usedSessions: Int) -> Int { max(0, limit - max(0, usedSessions)) }
}

/// Persists the number of consumed free sessions. Implementations: Keychain (app), in-memory (tests).
public protocol UsageCounterStore: AnyObject {
    func load() -> Int
    func save(_ value: Int)
}

public final class InMemoryUsageCounterStore: UsageCounterStore {
    private var value: Int
    public init(_ value: Int = 0) { self.value = value }
    public func load() -> Int { value }
    public func save(_ value: Int) { self.value = value }
}

/// Counts consumed sessions exactly once per device session (idempotent per sessionKey).
public final class FreeSessionLedger {
    private let store: UsageCounterStore
    private var countedKeys: Set<String> = []

    public init(store: UsageCounterStore) { self.store = store }

    public var used: Int { store.load() }

    /// Records a consumed session. `sessionKey` = "<deviceId>:<sessionId>" so a duplicated ACK is not double counted.
    @discardableResult
    public func recordStartedSession(sessionKey: String) -> Int {
        guard !countedKeys.contains(sessionKey) else { return store.load() }
        countedKeys.insert(sessionKey)
        let next = store.load() + 1
        store.save(next)
        return next
    }
}
