import Foundation

/// Maps a token total onto mechanical wheels that only ever turn forward.
/// At midnight the reading doesn't snap back to zero: every wheel rolls on to the next 000…0.
public struct Odometer: Equatable, Sendable {
    public let digits: Int
    public private(set) var base = 0

    public init(digits: Int) { self.digits = digits }

    public var modulus: Int { Self.pow10(digits) }

    public func position(total: Int) -> Int { base + total }

    /// Advances `base` to the next full revolution so a reading of `total` becomes zero on the dial.
    public mutating func rollOver(from total: Int) {
        let reached = base + total
        base = (reached + modulus - 1) / modulus * modulus
    }

    /// One integer per wheel, most significant first. A wheel shows `value % 10`; animating
    /// between consecutive integers rolls it forward, including 9 → 0.
    public func wheels(position: Int) -> [Int] {
        (0..<digits).reversed().map { position / Self.pow10($0) }
    }

    static func pow10(_ n: Int) -> Int { (0..<n).reduce(1) { acc, _ in acc * 10 } }
}
