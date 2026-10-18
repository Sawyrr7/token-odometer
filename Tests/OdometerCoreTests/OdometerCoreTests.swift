import XCTest
@testable import OdometerCore

final class OdometerCoreTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    private func date(_ s: String) -> Date { ISODate.parse(s)! }

    private func usage(_ id: String, _ time: String, out: Int, read: Int = 0, model: ModelFamily = .opus) -> ParsedUsage {
        ParsedUsage(messageID: id, time: date(time), model: model, counts: TokenCounts(input: 1, output: out, cacheRead: read))
    }

    func testParsesAssistantUsageLine() {
        let line = #"{"type":"assistant","timestamp":"2026-10-18T14:14:05.326Z","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_creation_input_tokens":1092,"cache_read_input_tokens":115748,"output_tokens":5952}}}"#
        let parsed = TranscriptParser.parse(line: Data(line.utf8))
        XCTAssertEqual(parsed?.messageID, "msg_1")
        XCTAssertEqual(parsed?.model, .opus)
        XCTAssertEqual(parsed?.counts, TokenCounts(input: 2, output: 5952, cacheCreation: 1092, cacheRead: 115748))
        XCTAssertEqual(parsed?.counts.total(includingCacheReads: false), 7046)
    }

    func testIgnoresNonAssistantAndBrokenLines() {
        XCTAssertNil(TranscriptParser.parse(line: Data(#"{"type":"user","usage":1}"#.utf8)))
        XCTAssertNil(TranscriptParser.parse(line: Data(#"{"usage": oops"#.utf8)))
    }

    func testRepeatedLinesForOneMessageCountOnce() {
        let now = date("2026-10-18T15:00:00Z")
        var tally = Tally(now: now, tripStart: now.addingTimeInterval(-86_400), calendar: calendar)
        tally.apply(usage("m", "2026-10-18T14:00:00Z", out: 10), now: now)
        tally.apply(usage("m", "2026-10-18T14:00:01Z", out: 50), now: now)
        tally.apply(usage("m", "2026-10-18T14:00:01Z", out: 50), now: now)
        XCTAssertEqual(tally.today.output, 50)
        XCTAssertEqual(tally.trip.output, 50)
    }

    func testYesterdayCountsForTripButNotToday() {
        let now = date("2026-10-18T15:00:00Z")   // 10:00 in Chicago
        var tally = Tally(now: now, tripStart: date("2026-10-16T00:00:00Z"), calendar: calendar)
        tally.apply(usage("old", "2026-10-18T04:59:00Z", out: 100), now: now)   // 23:59 the day before
        tally.apply(usage("new", "2026-10-18T05:01:00Z", out: 7, model: .haiku), now: now)
        XCTAssertEqual(tally.today.output, 7)
        XCTAssertEqual(tally.todayByModel[.haiku]?.output, 7)
        XCTAssertEqual(tally.trip.output, 107)
    }

    func testMidnightStartsAFreshDay() {
        let now = date("2026-10-18T15:00:00Z")
        var tally = Tally(now: now, tripStart: now, calendar: calendar)
        tally.apply(usage("a", "2026-10-18T15:00:00Z", out: 5), now: now)
        XCTAssertFalse(tally.rollDayIfNeeded(now: date("2026-10-19T04:00:00Z")))
        XCTAssertTrue(tally.rollDayIfNeeded(now: date("2026-10-19T05:30:00Z")))
        XCTAssertEqual(tally.today, .zero)
        XCTAssertEqual(tally.trip.output, 5)
    }

    func testSpeedIsTokensPerMinuteOverTheLastMinute() {
        let now = date("2026-10-18T15:00:00Z")
        var tally = Tally(now: now, tripStart: now, calendar: calendar)
        tally.apply(usage("old", "2026-10-18T14:58:00Z", out: 999), now: now)
        tally.apply(usage("a", "2026-10-18T14:59:30Z", out: 99, read: 1000), now: now)
        XCTAssertEqual(tally.speed(now: now, includingCacheReads: false), 100)
        XCTAssertEqual(tally.speed(now: now, includingCacheReads: true), 1100)
    }

    func testResetTripZeroesOnlyTheTrip() {
        let now = date("2026-10-18T15:00:00Z")
        var tally = Tally(now: now, tripStart: now.addingTimeInterval(-60), calendar: calendar)
        tally.apply(usage("a", "2026-10-18T14:59:30Z", out: 9), now: now)
        tally.resetTrip(at: now)
        XCTAssertEqual(tally.trip, .zero)
        XCTAssertEqual(tally.today.output, 10 - 1)
        tally.apply(usage("b", "2026-10-18T15:00:10Z", out: 4), now: now)
        XCTAssertEqual(tally.trip.output, 4)
    }

    func testWheelsAreMostSignificantFirst() {
        let odo = Odometer(digits: 4)
        XCTAssertEqual(odo.wheels(position: 1234).map { $0 % 10 }, [1, 2, 3, 4])
        XCTAssertEqual(odo.wheels(position: 51234).map { $0 % 10 }, [1, 2, 3, 4])
    }

    func testRolloverMovesForwardToAllZeros() {
        var odo = Odometer(digits: 3)
        odo.rollOver(from: 456)
        XCTAssertEqual(odo.position(total: 0), 1000)
        XCTAssertEqual(odo.wheels(position: odo.position(total: 0)).map { $0 % 10 }, [0, 0, 0])
        odo.rollOver(from: 0)
        XCTAssertEqual(odo.base, 1000, "an already-zero dial stays put")
    }

    func testScannerReadsTranscriptsUnderTheRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("-Users-me-proj/sess/subagents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("agent.jsonl")
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        let line = #"{"type":"assistant","timestamp":"\#(stamp)","message":{"id":"x","model":"claude-haiku-5-5","usage":{"input_tokens":3,"output_tokens":4}}}"# + "\n"
        try Data(line.utf8).write(to: file)

        let scanner = TranscriptScanner(root: root, now: now, tripStart: now.addingTimeInterval(-60))
        scanner.poll(now: now)
        XCTAssertEqual(scanner.tally.today.total(includingCacheReads: false), 7)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.replacingOccurrences(of: #""id":"x""#, with: #""id":"y""#).utf8))
        try handle.close()
        scanner.poll(now: now)
        XCTAssertEqual(scanner.tally.today.total(includingCacheReads: false), 14)
    }

    func testLifetimeKeepsClimbingAcrossMidnight() {
        let now = date("2026-10-18T15:00:00Z")
        var tally = Tally(now: now, tripStart: now, lifetimeBase: 6_400_000_000, lifetimeAnchor: now, calendar: calendar)
        tally.apply(usage("before", "2026-10-18T14:00:00Z", out: 50), now: now)
        tally.apply(usage("a", "2026-10-18T15:00:01Z", out: 9, read: 90), now: now)
        XCTAssertEqual(tally.lifetime, 6_400_000_100)

        let tomorrow = date("2026-10-19T06:00:00Z")
        XCTAssertTrue(tally.rollDayIfNeeded(now: tomorrow))
        XCTAssertEqual(tally.lifetime, 6_400_000_100)
        XCTAssertEqual(tally.lifetimeBase, 6_400_000_100)
        XCTAssertEqual(tally.lifetimeAnchor, calendar.startOfDay(for: tomorrow))
        tally.apply(usage("b", "2026-10-19T06:00:01Z", out: 4), now: tomorrow)
        XCTAssertEqual(tally.lifetime, 6_400_000_105)
        XCTAssertEqual(tally.today.output, 4)
    }

    func testSetLifetimeStartsFromTheGivenValue() {
        let now = date("2026-10-18T15:00:00Z")
        var tally = Tally(now: now, tripStart: now, calendar: calendar)
        tally.apply(usage("a", "2026-10-18T15:00:00Z", out: 9), now: now)
        tally.setLifetime(42, at: now.addingTimeInterval(1))
        XCTAssertEqual(tally.lifetime, 42)
        tally.apply(usage("b", "2026-10-18T15:00:02Z", out: 7), now: now)
        XCTAssertEqual(tally.lifetime, 50)
    }
}
