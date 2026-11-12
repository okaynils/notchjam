import Foundation
import Testing
#if canImport(NotchjamCore)
@testable import NotchjamCore
#else
@testable import notchjam
#endif

struct LyricsParserTests {
    @Test func timestampsAndRepeatedTags() {
        let lines = LyricsParser.parse("[ar:someone]\n[01:02.3][00:04.250] words\n[00:05:50]next\n[bad]oops\n[00:61]invalid")
        #expect(lines.map(\.time) == [4.25, 5.5, 62.3])
        #expect(lines.map(\.text) == ["words", "next", "words"])
    }
    @Test func offsetsAndBlankBreaks() {
        let lines = LyricsParser.parse("[00:01]a\r\n[00:02]\r\n[offset:-500]")
        #expect(lines == [LyricLine(time: 0.5, text: "a"), LyricLine(time: 1.5, text: "")])
    }
    @Test func duplicateTimesTranslationsAndWordTags() {
        let lines = LyricsParser.parse("[00:01]hello\n[00:01]bonjour\n[00:01]hello\n[00:03]<00:03.00>world")
        #expect(lines.count == 2)
        #expect(lines[0].text == "hello\nbonjour")
        #expect(lines[1].text == "world")
    }
    @Test func malformedAndUnicode() {
        #expect(LyricsParser.parse("no timestamps").isEmpty)
        #expect(LyricsParser.parse("[00:00.123]夜の音 🎵").first?.text == "夜の音 🎵")
        #expect(LyricsParser.parse("[00:00.01]a\n[offset:-100]").first?.time == 0)
    }
}

struct SynchronizationTests {
    @Test func boundariesAndSeeking() {
        let lyrics = Lyrics(lines: LyricsParser.parse("[00:02]a\n[00:04]b\n[00:06]"), plain: nil, instrumental: false)
        #expect(lyrics.activeIndex(at: 0) == nil)
        #expect(lyrics.activeIndex(at: 2) == 0)
        #expect(lyrics.activeIndex(at: 5.99) == 1)
        #expect(lyrics.activeIndex(at: 6) == 2)
        #expect(lyrics.activeIndex(at: 3) == 0)
        #expect(lyrics.activeIndex(at: 100) == 2)
    }
    @Test func clockPausesSeeksAndClamps() {
        var clock = PlaybackClock(snapshot: PlaybackSnapshot(track: MockPlayback.track, state: .playing, position: 10, sampledAt: 100))
        #expect(clock.position(at: 103) == 13)
        #expect(clock.position(at: 200) == 48)
        clock.snapshot = PlaybackSnapshot(track: MockPlayback.track, state: .paused, position: 4, sampledAt: 103)
        #expect(clock.position(at: 200) == 4)
        clock.snapshot = PlaybackSnapshot(track: MockPlayback.track, state: .playing, position: 2, sampledAt: 200)
        #expect(clock.position(at: 201) == 3)
        #expect(clock.position(at: 199) == 2)
    }
}

struct MatchingTests {
    let track = Track(id: "id", title: "Hello - 2011 Remaster", artist: "Beyoncé", album: "Home", duration: 200)
    func record(_ title: String = "Hello", artist: String = "Beyonce", album: String = "Home", duration: Double = 200, synced: String? = "[00:01]hello") -> LyricsRecord {
        LyricsRecord(id: 1, trackName: title, artistName: artist, albumName: album, duration: duration,
                     instrumental: false, plainLyrics: "hello", syncedLyrics: synced)
    }
    @Test func normalizesAndMatches() {
        #expect(TrackMatcher.score(record(), for: track) != nil)
        #expect(TrackMatcher.score(record("HELLO!"), for: track) != nil)
    }
    @Test func rejectsWrongRecordings() {
        #expect(TrackMatcher.score(record("Hello (Live)"), for: track) == nil)
        #expect(TrackMatcher.score(record(artist: "Cover Band"), for: track) == nil)
        #expect(TrackMatcher.score(record(duration: 210), for: track) == nil)
    }
    @Test func ranksAlbumAndTiming() {
        let wrongAlbum = record(album: "Other", duration: 204)
        let correct = record()
        #expect(TrackMatcher.best([wrongAlbum, correct], for: track)?.albumName == "Home")
    }
}

struct ShortcutTests {
    @Test func twoDistinctTaps() {
        var r = OptionTapRecognizer()
        let fired1 = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0)
        #expect(!fired1)
        let fired2 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.05)
        #expect(!fired2)
        let fired3 = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0.15)
        #expect(!fired3)
        let fired4 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.2)
        #expect(fired4)
        let fired5 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.21)
        #expect(!fired5)
    }
    @Test func rejectsChordsAndHeldKeys() {
        var r = OptionTapRecognizer()
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0)
        r.cancel() // A normal key, right Option, mouse event, or another modifier.
        let fired6 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.05)
        #expect(!fired6)
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0.1)
        let fired7 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.15)
        #expect(!fired7)
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: true, at: 0.2)
        let fired8 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.25)
        #expect(!fired8)
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 1)
        let fired9 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 2)
        #expect(!fired9)
    }
    @Test func relaxedHumanPace() {
        var r = OptionTapRecognizer()
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0)
        _ = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.12)
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0.45)
        let fired = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.58)
        #expect(fired)
    }
    @Test func heldSecondTap() {
        var r = OptionTapRecognizer()
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0)
        _ = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.1)
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0.2)
        let fired = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.7)
        #expect(!fired)
    }
    @Test func slowTapsAndSecondTapChord() {
        var r = OptionTapRecognizer()
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0)
        _ = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.05)
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0.5)
        let fired10 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.55)
        #expect(!fired10)
        _ = r.keyChanged(leftOptionDown: true, otherModifiers: false, at: 0.6)
        r.cancel()
        let fired11 = r.keyChanged(leftOptionDown: false, otherModifiers: false, at: 0.65)
        #expect(!fired11)
    }
}
