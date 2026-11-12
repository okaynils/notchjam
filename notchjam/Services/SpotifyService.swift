import AppKit

/// Actor isolation keeps synchronous Apple Events away from the UI and serializes requests.
actor SpotifyService {
    enum Failure: Error { case permissionDenied, unavailable, invalidResponse }

    func snapshot() throws -> PlaybackSnapshot {
        // Raw dictionary codes avoid resolving/launching Spotify to compile its terminology.
        let source = """
        set spotifyBundleID to "com.spotify.client"
        with timeout of 3 seconds
            if application id spotifyBundleID is not running then return {"stopped"}
            tell application id spotifyBundleID
                set s to «property pPlS»
                if s is «constant ePlSkPSS» then return {"stopped"}
                set t to «property pTrk»
                set stateName to "paused"
                if s is «constant ePlSkPSP» then set stateName to "playing"
                set trackID to ""
                try
                    set trackID to «property ID  » of t
                end try
                return {stateName, «property pnam» of t, «property pArt» of t, «property pAlb» of t, «property pDur» of t, «property pPos», trackID}
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { throw Failure.invalidResponse }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 { throw Failure.permissionDenied }
            throw Failure.unavailable
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard let stateText = result.atIndex(1)?.stringValue, let state = PlaybackState(rawValue: stateText) else {
            throw Failure.invalidResponse
        }
        if state == .stopped { return PlaybackSnapshot(track: nil, state: state, position: 0, sampledAt: now) }
        guard result.numberOfItems == 7,
              let title = result.atIndex(2)?.stringValue,
              let artist = result.atIndex(3)?.stringValue,
              let album = result.atIndex(4)?.stringValue else { throw Failure.invalidResponse }
        // Spotify's desktop implementation reports duration in milliseconds, position in seconds.
        let duration = (result.atIndex(5)?.doubleValue ?? 0) / 1000
        let position = result.atIndex(6)?.doubleValue ?? 0
        guard duration.isFinite, duration > 0, position.isFinite else { throw Failure.invalidResponse }
        let track = Track(id: result.atIndex(7)?.stringValue ?? "", title: title, artist: artist, album: album, duration: duration)
        return PlaybackSnapshot(track: track, state: state, position: position, sampledAt: now)
    }
}
