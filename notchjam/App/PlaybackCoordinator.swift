import AppKit
import Observation

@MainActor @Observable
final class PlaybackCoordinator {
    enum Status: Equatable { case idle, loading, ready, missing, message(String) }
    private(set) var track: Track?
    private(set) var state = PlaybackState.stopped
    private(set) var lyrics: Lyrics?
    private(set) var status = Status.idle
    private(set) var activeIndex: Int?
    private(set) var position: Double = 0
    var visible = false
    var pinned = false
    var expanded = false
    var notchInset: CGFloat = 0
    private let spotify = SpotifyService()
    private let lyricsService = LyricsService()
    let preferences: Preferences
    private var clock = PlaybackClock()
    private var polling: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var lookup: Task<Void, Never>?
    private var generation = UUID()
    private var mockStart = ProcessInfo.processInfo.systemUptime
    private var mockPausedAt: Double?
    private var suspended = false
    private var refreshing = false
    private var retryAt = Date.distantFuture
    private(set) var automationDenied = false

    init(preferences: Preferences) { self.preferences = preferences }

    func start() {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.suspended { await self.refresh() }
                let seconds = self.visible ? 0.75 : (self.state == .playing ? 2.0 : 4.0)
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            }
        }
    }

    func stop() {
        polling?.cancel(); ticker?.cancel(); lookup?.cancel()
    }

    func setVisible(_ value: Bool) {
        visible = value
        ticker?.cancel()
        if value {
            tick()
            Task { await refresh() }
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tick()
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
        }
    }

    func sleep() {
        suspended = true
        generation = UUID()
        lookup?.cancel()
        polling?.cancel()
        ticker?.cancel()
    }
    func wake() { suspended = false; restartSource() }

    func restartSource() {
        generation = UUID()
        lookup?.cancel()
        track = nil; lyrics = nil; activeIndex = nil; clock.snapshot = nil
        state = .stopped
        status = .idle
        mockStart = ProcessInfo.processInfo.systemUptime
        mockPausedAt = nil
        start()
        if visible { setVisible(true) }
    }

    func connectSpotify() {
        automationDenied = false
        preferences.spotifyEnabled = true
        restartSource()
    }

    func refresh() async {
        guard !refreshing, !suspended else { return }
        refreshing = true
        defer { refreshing = false }
        if preferences.mockPlayback {
            let elapsed = mockPausedAt ?? (ProcessInfo.processInfo.systemUptime - mockStart)
            let snapshot = PlaybackSnapshot(track: MockPlayback.track, state: mockPausedAt == nil ? .playing : .paused,
                                            position: elapsed.truncatingRemainder(dividingBy: MockPlayback.track.duration),
                                            sampledAt: ProcessInfo.processInfo.systemUptime)
            accept(snapshot, mock: true)
            return
        }
        guard preferences.spotifyEnabled else {
            unavailable(automationDenied
                ? "Allow Spotify in System Settings → Privacy & Security → Automation, then reconnect in Preferences."
                : "Connect Spotify in Preferences to see your lyrics.")
            return
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil else {
            unavailable("Install Spotify’s desktop app to get started.")
            return
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            unavailable("Open Spotify and play something you love.")
            return
        }
        let requestGeneration = generation
        do {
            let snapshot = try await spotify.snapshot()
            guard requestGeneration == generation, !Task.isCancelled, !suspended else { return }
            accept(snapshot, mock: false)
        } catch {
            guard requestGeneration == generation, !Task.isCancelled, !suspended else { return }
            if let failure = error as? SpotifyService.Failure, case .permissionDenied = failure {
                automationDenied = true
                preferences.spotifyEnabled = false
                unavailable("Allow Spotify in System Settings → Privacy & Security → Automation, then reconnect in Preferences.")
            } else { unavailable("Spotify isn’t responding. Waiting for playback…") }
        }
    }

    private func accept(_ snapshot: PlaybackSnapshot, mock: Bool) {
        let changed = track != snapshot.track
        clock.snapshot = snapshot
        state = snapshot.state
        track = snapshot.track
        if track == nil { unavailable("Play a song in Spotify."); return }
        if changed || status == .idle {
            generation = UUID()
            lookup?.cancel()
            lyrics = nil
            activeIndex = nil
            if mock { lyrics = MockPlayback.lyrics; status = .ready }
            else { loadLyrics() }
        }
        if case .message = status, visible, Date() >= retryAt { loadLyrics() }
        tick()
    }

    func retryLyrics() { guard track != nil else { connectSpotify(); return }; loadLyrics() }

    private func loadLyrics() {
        guard let track else { return }
        lookup?.cancel()
        let token = UUID()
        generation = token
        status = .loading
        retryAt = .distantFuture
        lookup = Task { [weak self, lyricsService] in
            do {
                // Debounce skips without delaying cached peeks on the same track.
                try await Task.sleep(for: .milliseconds(200))
                let result = try await lyricsService.lyrics(for: track)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.lyrics = result
                self.status = result == nil ? .missing : .ready
                self.tick()
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if case LyricsService.Failure.rateLimited(let until) = error {
                    self.retryAt = until
                } else { self.retryAt = Date().addingTimeInterval(30) }
                self.status = .message((error as? LyricsService.Failure)?.localizedDescription ?? "You’re offline or LRCLIB is unavailable. Try again when connected.")
            }
        }
    }

    private func unavailable(_ message: String) {
        if track != nil { generation = UUID(); lookup?.cancel() }
        track = nil; lyrics = nil; activeIndex = nil; state = .stopped; clock.snapshot = nil
        status = .message(message)
    }
    private func tick() {
        position = clock.position(at: ProcessInfo.processInfo.systemUptime)
        activeIndex = lyrics?.activeIndex(at: position)
    }

    var mockPaused: Bool { mockPausedAt != nil }
    func mockTogglePause() {
        if let paused = mockPausedAt { mockStart = ProcessInfo.processInfo.systemUptime - paused; mockPausedAt = nil }
        else { mockPausedAt = ProcessInfo.processInfo.systemUptime - mockStart }
        Task { await refresh() }
    }
    func mockSeek() {
        if mockPausedAt != nil { mockPausedAt = (mockPausedAt! + 10).truncatingRemainder(dividingBy: 48) }
        else { mockStart -= 10 }
        Task { await refresh() }
    }
}
