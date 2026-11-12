import SwiftUI

struct LyricsView: View {
    @Bindable var model: PlaybackCoordinator
    let onPin: () -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation? {
        model.preferences.animations && !reduceMotion ? .easeInOut(duration: 0.24) : nil
    }
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notchInset)
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    if model.preferences.showHeader, let track = model.track {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                            Text(track.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                        }.lineLimit(1)
                    } else {
                        Text("notchjam").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer(minLength: 6)
                    if model.state == .paused {
                        Image(systemName: "pause.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).accessibilityLabel("Paused")
                    }
                    Button(action: onPin) { Image(systemName: model.pinned ? "pin.fill" : "pin") }
                        .help(model.pinned ? "Unpin lyrics" : "Keep lyrics visible")
                        .accessibilityLabel(model.pinned ? "Unpin lyrics" : "Pin lyrics")
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .help("Hide lyrics").accessibilityLabel("Hide lyrics")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: 30)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(animation, value: model.activeIndex)
                HStack {
                    Text(model.preferences.mockPlayback ? "demo playback" : "lyrics by LRCLIB")
                    Spacer()
                    if model.pinned { Text("pinned") }
                    else { Text(model.preferences.doubleOption ? "⌥ ⌥ to hide" : "\(model.preferences.shortcut.displayName) to hide") }
                }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.25))
            }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 15)
        }
        .background(.black)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: model.notchInset > 0 ? 5 : 22,
                                         bottomLeadingRadius: 24, bottomTrailingRadius: 24,
                                         topTrailingRadius: model.notchInset > 0 ? 5 : 22))
        .scaleEffect(x: model.expanded ? 1 : 0.48, y: model.expanded ? 1 : 0.03, anchor: .top)
        .opacity(model.expanded ? 1 : 0)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .idle: message("Ready when you are", detail: "Play a song in Spotify.")
        case .loading:
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Finding the words…").font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
            }
        case .missing: message("Just the music, for now", detail: "No lyrics found for this recording.")
        case .message(let text):
            VStack(spacing: 10) {
                message("A quiet moment", detail: text)
                if model.track != nil { Button("Try again") { model.retryLyrics() }.buttonStyle(.plain).font(.system(size: 11)) }
            }
        case .ready:
            if let lyrics = model.lyrics {
                if lyrics.instrumental { message("No words needed", detail: "This track is instrumental.") }
                else if !lyrics.lines.isEmpty { synced(lyrics) }
                else if let plain = lyrics.plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 8) {
                        Text("Unsynchronized lyrics · scroll to read").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        ScrollView {
                            Text(plain).font(.system(size: 16, weight: .medium)).lineSpacing(7)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                        }.scrollIndicators(.hidden)
                    }
                } else { message("Just the music, for now", detail: "No lyrics available.") }
            }
        }
    }

    private func synced(_ lyrics: Lyrics) -> some View {
        let current = model.activeIndex ?? -1
        return VStack(spacing: 12) {
            line(current - 1, lyrics: lyrics, prominent: false)
            line(current, lyrics: lyrics, prominent: true)
            line(current + 1, lyrics: lyrics, prominent: false)
        }
        .id(current)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 7)), removal: .opacity))
        .animation(animation, value: current)
        .accessibilityElement(children: .combine)
    }
    private func line(_ index: Int, lyrics: Lyrics, prominent: Bool) -> some View {
        let text = lyrics.lines.indices.contains(index) ? lyrics.lines[index].text : ""
        return Text(text.isEmpty ? (prominent ? "♪" : " ") : text)
            .font(.system(size: prominent ? model.preferences.textSize : 14, weight: prominent ? .semibold : .regular))
            .foregroundStyle(.white.opacity(prominent ? 0.98 : 0.32))
            .multilineTextAlignment(.center)
            .lineLimit(prominent ? 3 : 1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: prominent ? 50 : 18)
    }
    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 9) {
            Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }
}
