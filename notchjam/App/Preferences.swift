import Foundation
import Observation

@MainActor @Observable
final class Preferences {
    private let defaults: UserDefaults
    var toggleMode: Bool { didSet { defaults.set(toggleMode, forKey: "toggleMode") } }
    var shortcut: GlobalShortcut { didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "globalShortcut") } }
    var doubleOption: Bool { didSet { defaults.set(doubleOption, forKey: "doubleOption") } }
    var dismissal: Double { didSet { defaults.set(dismissal, forKey: "dismissal") } }
    var animations: Bool { didSet { defaults.set(animations, forKey: "animations") } }
    var showHeader: Bool { didSet { defaults.set(showHeader, forKey: "showHeader") } }
    var textSize: Double { didSet { defaults.set(textSize, forKey: "textSize") } }
    var spotifyEnabled: Bool { didSet { defaults.set(spotifyEnabled, forKey: "spotifyEnabled") } }
    var mockPlayback = ProcessInfo.processInfo.arguments.contains("--mock")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["toggleMode": true, "doubleOption": true, "dismissal": 7.0, "animations": true,
                                    "showHeader": true, "textSize": 20.0, "spotifyEnabled": false])
        toggleMode = defaults.bool(forKey: "toggleMode")
        if let data = defaults.data(forKey: "globalShortcut"),
           let saved = try? JSONDecoder().decode(GlobalShortcut.self, from: data), saved.isValid {
            shortcut = saved
        } else { shortcut = .defaultShortcut }
        doubleOption = defaults.bool(forKey: "doubleOption")
        dismissal = min(30, max(3, defaults.double(forKey: "dismissal")))
        animations = defaults.bool(forKey: "animations")
        showHeader = defaults.bool(forKey: "showHeader")
        textSize = min(24, max(16, defaults.double(forKey: "textSize")))
        spotifyEnabled = defaults.bool(forKey: "spotifyEnabled")
    }
}
