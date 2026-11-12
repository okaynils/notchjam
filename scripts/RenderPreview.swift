import SwiftUI
import AppKit

@main
struct RenderCheck {
    @MainActor static func main() async throws {
        let defaults = UserDefaults(suiteName: "com.notchjam.render-check")!
        let preferences = Preferences(defaults: defaults)
        preferences.mockPlayback = true
        let model = PlaybackCoordinator(preferences: preferences)
        await model.refresh()
        model.mockSeek()
        await model.refresh()
        model.expanded = true
        let view = LyricsView(model: model, onPin: {}, onClose: {}).frame(width: 440, height: 248)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { throw NSError(domain: "Render", code: 1) }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/qa/panel.png"))
    }
}
