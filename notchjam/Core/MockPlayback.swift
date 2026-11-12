import Foundation

/// Original sample text; no copyrighted song lyrics are bundled.
enum MockPlayback {
    static let track = Track(id: "notchjam:demo", title: "A little room to listen", artist: "notchjam", album: "Quiet moments", duration: 48)
    static let lyrics = Lyrics(lines: LyricsParser.parse("""
    [00:00.00]
    [00:02.00]Let the day move softly
    [00:06.00]Leave a little room to listen
    [00:10.00]Every word a window
    [00:14.00]Every quiet moment yours
    [00:18.00]
    [00:22.00]Somewhere in the rhythm
    [00:26.00]Find the space between the lines
    [00:30.00]Let the world keep turning
    [00:34.00]We can take our time
    [00:39.00]A little room to listen
    [00:44.00]
    """), plain: nil, instrumental: false)
}
