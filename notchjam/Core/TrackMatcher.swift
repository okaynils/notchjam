import Foundation

enum TrackMatcher {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func searchTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"(?i)\s*(?:\([^)]*remaster[^)]*\)|-\s*(?:\d{4}\s*)?remaster.*)$"#,
                                   with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    static func score(_ candidate: LyricsRecord, for track: Track) -> Double? {
        let title = normalized(searchTitle(track.title))
        guard normalized(searchTitle(candidate.trackName)) == title,
              normalized(candidate.artistName) == normalized(track.artist),
              candidate.duration.isFinite, abs(candidate.duration - track.duration) <= 5 else { return nil }
        // Never choose a different live/remix version merely because it has synced lyrics.
        let albumBonus = normalized(candidate.albumName) == normalized(track.album) ? 8.0 : 0
        let syncBonus = candidate.lyrics.lines.isEmpty ? 0.0 : 3
        return 100 + albumBonus + syncBonus - abs(candidate.duration - track.duration) * 2
    }

    static func best(_ candidates: [LyricsRecord], for track: Track) -> LyricsRecord? {
        candidates.compactMap { candidate in score(candidate, for: track).map { (candidate, $0) } }
            .max { $0.1 < $1.1 }?.0
    }
}
