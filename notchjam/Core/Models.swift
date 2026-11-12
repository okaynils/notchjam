import Foundation

struct Track: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval

    var cacheKey: String { [id, title, artist, album, String(duration.rounded())].joined(separator: "\u{1f}") }
}

enum PlaybackState: String, Sendable { case playing, paused, stopped }

struct PlaybackSnapshot: Sendable {
    let track: Track?
    let state: PlaybackState
    let position: TimeInterval
    let sampledAt: TimeInterval
}

/// Monotonic uptime makes playback independent of wall-clock adjustments.
struct PlaybackClock: Sendable {
    var snapshot: PlaybackSnapshot?

    func position(at uptime: TimeInterval) -> TimeInterval {
        guard let snapshot else { return 0 }
        let elapsed = snapshot.state == .playing ? max(0, uptime - snapshot.sampledAt) : 0
        return min(max(0, snapshot.position + elapsed), snapshot.track?.duration ?? .greatestFiniteMagnitude)
    }
}

struct LyricLine: Codable, Equatable, Sendable, Identifiable {
    let time: TimeInterval
    let text: String
    var id: TimeInterval { time }
}

struct Lyrics: Codable, Equatable, Sendable {
    let lines: [LyricLine]
    let plain: String?
    let instrumental: Bool

    func activeIndex(at position: TimeInterval) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : low - 1
    }
}

struct LyricsRecord: Codable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?

    var lyrics: Lyrics {
        Lyrics(lines: LyricsParser.parse(syncedLyrics ?? ""), plain: plainLyrics, instrumental: instrumental)
    }
}
