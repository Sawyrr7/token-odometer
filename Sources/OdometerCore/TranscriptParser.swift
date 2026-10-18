import Foundation

public enum TranscriptParser {
    private static let usageMarker = Data(#""usage""#.utf8)

    /// Returns usage for an assistant line, or nil for anything else (including malformed JSON).
    public static func parse(line: Data) -> ParsedUsage? {
        // Most lines are not assistant usage lines; skip the JSON parse for them.
        guard line.range(of: usageMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let id = message["id"] as? String,
              let usage = message["usage"] as? [String: Any],
              let stamp = object["timestamp"] as? String,
              let time = ISODate.parse(stamp)
        else { return nil }

        return ParsedUsage(
            messageID: id, time: time,
            model: ModelFamily(modelID: message["model"] as? String ?? ""),
            counts: TokenCounts(
                input: int(usage["input_tokens"]),
                output: int(usage["output_tokens"]),
                cacheCreation: int(usage["cache_creation_input_tokens"]),
                cacheRead: int(usage["cache_read_input_tokens"])))
    }

    private static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
}
