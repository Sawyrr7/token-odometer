import Foundation

/// Tails every Claude Code transcript that could hold tokens for today or the trip.
/// Not thread-safe: call it from one serial queue.
public final class TranscriptScanner {
    /// Trip and lifetime never read further back than this, so a long gap can't make launch slow.
    public static let maxLookback: TimeInterval = 7 * 86_400

    public private(set) var tally: Tally
    private let root: URL
    private var tailers: [URL: LineTailer] = [:]
    private let calendar: Calendar

    public init(root: URL, now: Date, tripStart: Date, lifetimeBase: Int = 0, lifetimeAnchor: Date? = nil,
                calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
        self.tally = Tally(now: now, tripStart: tripStart, lifetimeBase: lifetimeBase,
                           lifetimeAnchor: lifetimeAnchor, calendar: calendar)
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// Reads whatever was appended since the last call. Returns true if the day rolled over.
    @discardableResult
    public func poll(now: Date) -> Bool {
        let rolled = tally.rollDayIfNeeded(now: now)
        let windowStart = min(
            calendar.startOfDay(for: now),
            max(min(tally.tripStart, tally.lifetimeAnchor), now.addingTimeInterval(-Self.maxLookback)))

        for url in transcripts(modifiedSince: windowStart) {
            let tailer = tailers[url] ?? LineTailer()
            tailers[url] = tailer
            tailer.forEachNewLine(from: url) { line in
                if let usage = TranscriptParser.parse(line: line) { tally.apply(usage, now: now) }
            }
        }
        return rolled
    }

    public func resetTrip(at now: Date) { tally.resetTrip(at: now) }

    public func setLifetime(_ value: Int, at now: Date) { tally.setLifetime(value, at: now) }

    public func speed(now: Date, includingCacheReads: Bool) -> Double {
        tally.speed(now: now, includingCacheReads: includingCacheReads)
    }

    private func transcripts(modifiedSince start: Date) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [] }
        var urls: [URL] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            if tailers[url] != nil { urls.append(url); continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified >= start { urls.append(url) }
        }
        return urls
    }
}
