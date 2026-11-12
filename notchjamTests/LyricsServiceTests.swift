import Foundation
import Testing
#if canImport(NotchjamCore)
@testable import NotchjamCore
#else
@testable import notchjam
#endif

private final class LyricsFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let title = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "track_name" }?.value ?? ""
        let isSearch = url.path.hasSuffix("search")
        var code = 200
        var body = ""
        if title == "Missing" { code = isSearch ? 200 : 404; body = "[]" }
        else if title == "PlainOfflineSearch" && isSearch { code = 503; body = "{}" }
        else if title == "Rate" { code = 429; body = "{}" }
        else if title == "Fallback" && !isSearch { code = 404; body = "{}" }
        else {
            let record = LyricsRecord(id: 42, trackName: title, artistName: "Artist", albumName: "Album", duration: 180,
                                      instrumental: title == "Instrumental", plainLyrics: title.hasPrefix("Plain") ? "just words" : nil,
                                      syncedLyrics: title.hasPrefix("Plain") || title == "Instrumental" ? nil : "[00:01]one\n[00:02]two")
            let data = isSearch ? try! JSONEncoder().encode([record]) : try! JSONEncoder().encode(record)
            body = String(decoding: data, as: UTF8.self)
        }
        let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "120", "Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class OfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

struct LyricsServiceTests {
    private func session(offline: Bool = false) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = offline ? [OfflineProtocol.self] : [LyricsFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func track(_ name: String) -> Track { Track(id: name, title: name, artist: "Artist", album: "Album", duration: 180) }

    @Test(arguments: ["Exact", "Fallback", "Plain", "PlainOfflineSearch", "Instrumental", "Missing"])
    func lookupAndPersistentCache(_ name: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = session()
        defer { session.invalidateAndCancel() }
        let service = LyricsService(session: session, directory: directory)
        let result = try await service.lyrics(for: track(name))
        switch name {
        case "Missing": #expect(result == nil)
        case "Plain", "PlainOfflineSearch": #expect(result?.plain == "just words"); #expect(result?.lines.isEmpty == true)
        case "Instrumental": #expect(result?.instrumental == true)
        default: #expect(result?.lines.count == 2)
        }
        let offline = self.session(offline: true)
        defer { offline.invalidateAndCancel() }
        let reopened = LyricsService(session: offline, directory: directory)
        let cached = try await reopened.lyrics(for: track(name))
        #expect(cached == result)
    }

    @Test func rateLimitAndCancellation() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = LyricsService(session: session, directory: directory)
        do { _ = try await service.lyrics(for: track("Rate")); Issue.record("Expected rate limit") }
        catch LyricsService.Failure.rateLimited(let until) { #expect(until.timeIntervalSinceNow > 120) }
        do { _ = try await service.lyrics(for: track("Exact")); Issue.record("Retry-After must apply across songs") }
        catch LyricsService.Failure.rateLimited { }
        let task = Task { try await service.lyrics(for: track("Other")) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
    }

    @Test func offlineDoesNotPoisonCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let offline = session(offline: true)
        defer { offline.invalidateAndCancel() }
        let service = LyricsService(session: offline, directory: directory)
        await #expect(throws: (any Error).self) { try await service.lyrics(for: track("Exact")) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
