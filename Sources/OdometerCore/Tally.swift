import Foundation

/// Running totals for today, the trip meter and the speedometer.
/// Lines for the same message repeat and grow (and resumed sessions copy history into new files),
/// so every message counts once, as the per-field max of everything seen for it.
public struct Tally {
    public private(set) var day: Date
    public private(set) var today = TokenCounts.zero
    public private(set) var todayByModel: [ModelFamily: TokenCounts] = [:]
    public private(set) var tripStart: Date
    public private(set) var trip = TokenCounts.zero
    /// The permanent reading: everything before `lifetimeAnchor` is folded into `lifetimeBase`.
    public private(set) var lifetimeBase: Int
    public private(set) var lifetimeAnchor: Date
    public private(set) var sinceAnchor = TokenCounts.zero

    private var seen: [String: TokenCounts] = [:]
    private var recent: [(time: Date, counts: TokenCounts)] = []
    private let calendar: Calendar
    static let recentWindow: TimeInterval = 300

    public init(now: Date, tripStart: Date, lifetimeBase: Int = 0, lifetimeAnchor: Date? = nil,
                calendar: Calendar = .current) {
        self.calendar = calendar
        self.day = calendar.startOfDay(for: now)
        self.tripStart = tripStart
        self.lifetimeBase = lifetimeBase
        self.lifetimeAnchor = lifetimeAnchor ?? now
    }

    /// Lifetime counts every token, cache reads included; it never goes back.
    public var lifetime: Int { lifetimeBase + sinceAnchor.total(includingCacheReads: true) }

    public mutating func setLifetime(_ value: Int, at now: Date) {
        lifetimeBase = value
        lifetimeAnchor = now
        sinceAnchor = .zero
    }

    /// Starts a fresh day when midnight has passed. Returns true when it did.
    public mutating func rollDayIfNeeded(now: Date) -> Bool {
        let start = calendar.startOfDay(for: now)
        guard start > day else { return false }
        day = start
        // Checkpoint the lifetime so a relaunch only has to re-read today's transcripts.
        lifetimeBase = lifetime
        lifetimeAnchor = start
        sinceAnchor = .zero
        today = .zero
        todayByModel = [:]
        return true
    }

    public mutating func apply(_ usage: ParsedUsage, now: Date) {
        let previous = seen[usage.messageID] ?? .zero
        let merged = previous.maxed(with: usage.counts)
        seen[usage.messageID] = merged
        let delta = merged - previous
        guard !delta.isZero else { return }

        if usage.time >= day {
            today = today + delta
            todayByModel[usage.model, default: .zero] = todayByModel[usage.model, default: .zero] + delta
        }
        if usage.time >= tripStart { trip = trip + delta }
        if usage.time >= lifetimeAnchor { sinceAnchor = sinceAnchor + delta }
        if usage.time >= now.addingTimeInterval(-Self.recentWindow) {
            recent.append((usage.time, delta))
        }
    }

    public mutating func resetTrip(at now: Date) {
        tripStart = now
        trip = .zero
    }

    /// Tokens per minute over the last `window` seconds.
    public mutating func speed(now: Date, window: TimeInterval = 60, includingCacheReads: Bool) -> Double {
        recent.removeAll { $0.time < now.addingTimeInterval(-Self.recentWindow) }
        let cutoff = now.addingTimeInterval(-window)
        let sum = recent.filter { $0.time >= cutoff }
            .reduce(0) { $0 + $1.counts.total(includingCacheReads: includingCacheReads) }
        return Double(sum) * 60 / window
    }
}
