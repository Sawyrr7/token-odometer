import Foundation

/// Reads only the bytes appended to a file since the last call, and returns whole lines.
final class LineTailer {
    private var offset: UInt64
    private var carry = Data()
    private var discarding = false
    private let maxLineBytes: Int
    private static let chunkBytes = 4 << 20

    init(startingAt offset: UInt64 = 0, maxLineBytes: Int = 64 << 20) {
        self.offset = offset
        self.maxLineBytes = maxLineBytes
    }

    static func size(of url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Streams each complete new line to `body` without holding the whole file in memory.
    /// (Today's transcripts can be hundreds of MB, so nothing here may be quadratic or accumulate.)
    func forEachNewLine(from url: URL, _ body: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return }
        if end < offset {                       // truncated or replaced: start over
            offset = 0
            carry.removeAll()
            discarding = false
        }
        while offset < end {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let chunk = try? handle.read(upToCount: min(Int(end - offset), Self.chunkBytes)),
                  !chunk.isEmpty
            else { break }
            offset += UInt64(chunk.count)
            carry.append(chunk)
            drain(body)
        }
    }

    func readNewLines(from url: URL) -> [Data] {
        var lines: [Data] = []
        forEachNewLine(from: url) { lines.append($0) }
        return lines
    }

    /// Emits every complete line in `carry`, then keeps only the unfinished tail (one copy per chunk).
    private func drain(_ body: (Data) -> Void) {
        var consumed = 0
        carry.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let end = base + raw.count
            var lineStart = base
            while lineStart < end, let found = memchr(lineStart, 0x0A, end - lineStart) {
                let length = lineStart.distance(to: UnsafeRawPointer(found))
                if discarding {
                    discarding = false          // that was the tail of an overlong line
                } else if length > 0, length <= maxLineBytes {
                    body(Data(bytes: lineStart, count: length))
                }
                lineStart = UnsafeRawPointer(found) + 1
            }
            consumed = base.distance(to: lineStart)
        }
        carry = carry.subdata(in: consumed..<carry.count)
        if carry.count > maxLineBytes {         // a line that never ends: drop it and its tail
            carry.removeAll()
            discarding = true
        }
    }
}
