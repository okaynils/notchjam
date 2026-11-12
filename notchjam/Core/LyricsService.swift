import Foundation
import CryptoKit

actor LyricsService {
    enum Failure: LocalizedError {
        case response(Int), rateLimited(Date)
        var errorDescription: String? {
            switch self {
            case .response: "Lyrics couldn’t be loaded. Try again shortly."
            case .rateLimited: "LRCLIB is busy. Please try again in a little while."
            }
        }
    }
    private struct CacheEntry: Codable {
        let version: Int
        let key: String
        let date: Date
        let lyrics: Lyrics?
    }
    private let session: URLSession
    private let directory: URL
    private var nextRequest = Date.distantPast
    private var requestInFlight = false

    init(session: URLSession = .shared, directory: URL? = nil) {
        self.session = session
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.notchjam.app/lyrics", isDirectory: true)
    }

    func lyrics(for track: Track) async throws -> Lyrics? {
        if let entry = readCache(track.cacheKey) { return entry.lyrics }
        let signature = [URLQueryItem(name: "track_name", value: track.title),
                         URLQueryItem(name: "artist_name", value: track.artist),
                         URLQueryItem(name: "album_name", value: track.album)]
        var exactQuery = signature
        if (1...3600).contains(track.duration) {
            exactQuery.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        var candidates: [LyricsRecord] = []
        if let data = try await request("get", query: exactQuery) {
            candidates.append(try JSONDecoder().decode(LyricsRecord.self, from: data))
        }
        if let match = TrackMatcher.best(candidates, for: track), !match.lyrics.lines.isEmpty || match.instrumental {
            try Task.checkCancellation()
            writeCache(match.lyrics, key: track.cacheKey)
            return match.lyrics
        }
        // Album is intentionally omitted here: reissues often have different album names.
        do {
            if let data = try await request("search", query: Array(signature.prefix(2))) {
                candidates += try JSONDecoder().decode([LyricsRecord].self, from: data)
            }
        } catch {
            try Task.checkCancellation()
            // Keep an exact plain-lyrics result when the optional sync search fails.
            if let match = TrackMatcher.best(candidates, for: track) {
                writeCache(match.lyrics, key: track.cacheKey)
                return match.lyrics
            }
            throw error
        }
        let cleaned = TrackMatcher.searchTitle(track.title)
        if TrackMatcher.best(candidates, for: track) == nil, cleaned != track.title,
           let data = try await request("search", query: [URLQueryItem(name: "track_name", value: cleaned), signature[1]]) {
            candidates += try JSONDecoder().decode([LyricsRecord].self, from: data)
        }
        try Task.checkCancellation()
        let result = TrackMatcher.best(candidates, for: track)?.lyrics
        writeCache(result, key: track.cacheKey)
        return result
    }

    private func request(_ endpoint: String, query: [URLQueryItem]) async throws -> Data? {
        while requestInFlight {
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        requestInFlight = true
        defer { requestInFlight = false }
        let delay = nextRequest.timeIntervalSinceNow
        if delay > 1 { throw Failure.rateLimited(nextRequest) }
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        // Reserve before suspension so rapid song changes still obey throttling.
        nextRequest = Date().addingTimeInterval(0.3)
        var components = URLComponents(string: "https://lrclib.net/api/" + endpoint)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("notchjam/1.0 (https://github.com/okaynils/notchjam)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw Failure.response(0) }
        if response.statusCode == 404 { return nil }
        if response.statusCode == 429 || response.statusCode == 503 {
            let value = response.value(forHTTPHeaderField: "Retry-After") ?? "60"
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let seconds = Double(value) ?? formatter.date(from: value)?.timeIntervalSinceNow ?? 60
            nextRequest = Date().addingTimeInterval(max(1, seconds) * 1.15)
            throw Failure.rateLimited(nextRequest)
        }
        guard response.statusCode == 200 else { throw Failure.response(response.statusCode) }
        guard data.count <= 2_000_000 else { throw Failure.response(0) }
        return data
    }

    private func url(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }
    private func readCache(_ key: String) -> CacheEntry? {
        guard let data = try? Data(contentsOf: url(for: key)),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
              entry.version == 1, entry.key == key,
              Date().timeIntervalSince(entry.date) < (entry.lyrics == nil ? 6 * 3600 : 30 * 86400) else { return nil }
        return entry
    }
    private func writeCache(_ lyrics: Lyrics?, key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let entry = CacheEntry(version: 1, key: key, date: Date(), lyrics: lyrics)
            try JSONEncoder().encode(entry).write(to: url(for: key), options: .atomic)
            // Bound disk use; oldest entries are expendable, never user documents.
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "json" }
            if files.count > 500 {
                let oldest = files.sorted {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
                    ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
                for file in oldest.prefix(files.count - 500) { try? FileManager.default.removeItem(at: file) }
            }
        } catch { /* A read-only/full cache must never prevent showing fetched lyrics. */ }
    }
}
