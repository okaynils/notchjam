import Foundation

/// Handles repeated tags, fractional seconds, offsets, blank musical breaks, and malformed input.
enum LyricsParser {
    static func parse(_ source: String) -> [LyricLine] {
        let timestamp = /\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]/
        let offsetTag = /\[offset:\s*([+-]?\d+)\s*\]/
        let offset = source.matches(of: offsetTag).last.flatMap { Double($0.1) }.map { $0 / 1000 } ?? 0
        var entries: [(Double, String, Int)] = []
        for row in source.components(separatedBy: .newlines) {
            let matches = row.matches(of: timestamp)
            guard let last = matches.last else { continue }
            let text = String(row[last.range.upperBound...])
                .replacingOccurrences(of: #"<\d{1,3}:[0-5]\d(?:\.\d{1,3})?>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            for match in matches {
                guard let minutes = Double(match.1), let seconds = Double(match.2) else { continue }
                let fraction = match.3.flatMap { Double("0." + $0) } ?? 0
                entries.append((max(0, minutes * 60 + seconds + fraction + offset), text, entries.count))
            }
        }
        entries.sort { $0.0 == $1.0 ? $0.2 < $1.2 : $0.0 < $1.0 }
        var lines: [LyricLine] = []
        for (time, text, _) in entries {
            if let last = lines.last, last.time == time {
                lines.removeLast()
                let combined = (last.text.components(separatedBy: "\n") + [text]).filter { !$0.isEmpty }.reduce(into: [String]()) {
                    if !$0.contains($1) { $0.append($1) }
                }.joined(separator: "\n")
                lines.append(LyricLine(time: time, text: combined))
            } else { lines.append(LyricLine(time: time, text: text)) }
        }
        return lines
    }
}
