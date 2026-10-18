import Foundation

public enum ModelFamily: String, CaseIterable, Sendable {
    case opus, sonnet, haiku, fable, other

    public init(modelID: String) {
        let id = modelID.lowercased()
        if id.contains("opus") { self = .opus }
        else if id.contains("sonnet") { self = .sonnet }
        else if id.contains("haiku") { self = .haiku }
        else if id.contains("fable") { self = .fable }
        else { self = .other }
    }

    public var label: String { rawValue.capitalized }
}

public struct TokenCounts: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }

    public static let zero = TokenCounts()

    /// The odometer reading. Cache reads re-count the same context every turn, so they are opt-in.
    public func total(includingCacheReads: Bool) -> Int {
        input + output + cacheCreation + (includingCacheReads ? cacheRead : 0)
    }

    public var isZero: Bool { self == .zero }

    public func maxed(with other: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: max(input, other.input), output: max(output, other.output),
            cacheCreation: max(cacheCreation, other.cacheCreation), cacheRead: max(cacheRead, other.cacheRead))
    }

    public static func + (l: TokenCounts, r: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: l.input + r.input, output: l.output + r.output,
            cacheCreation: l.cacheCreation + r.cacheCreation, cacheRead: l.cacheRead + r.cacheRead)
    }

    public static func - (l: TokenCounts, r: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: l.input - r.input, output: l.output - r.output,
            cacheCreation: l.cacheCreation - r.cacheCreation, cacheRead: l.cacheRead - r.cacheRead)
    }
}

public struct ParsedUsage: Equatable, Sendable {
    public let messageID: String
    public let time: Date
    public let model: ModelFamily
    public let counts: TokenCounts

    public init(messageID: String, time: Date, model: ModelFamily, counts: TokenCounts) {
        self.messageID = messageID
        self.time = time
        self.model = model
        self.counts = counts
    }
}

enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String) -> Date? {
        // The formatter is only reliable with millisecond precision, so trim longer fractions.
        let trimmed = string.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return withFraction.date(from: trimmed) ?? plain.date(from: trimmed)
    }
}
