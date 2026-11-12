import Foundation
import Testing
import Carbon
#if canImport(NotchjamCore)
@testable import NotchjamCore
#else
@testable import notchjam
#endif

struct ShortcutSettingsTests {
    @Test func toggleModeOverridesTimer() {
        #expect(PanelDismissal.delay(visible: true, pinned: false, toggleMode: true, duration: 7) == nil)
        #expect(PanelDismissal.delay(visible: true, pinned: false, toggleMode: false, duration: 7) == 7)
        #expect(PanelDismissal.delay(visible: true, pinned: true, toggleMode: false, duration: 7) == nil)
        #expect(PanelDismissal.delay(visible: false, pinned: false, toggleMode: false, duration: 7) == nil)
    }

    @Test func customShortcutRoundTrip() throws {
        let shortcut = GlobalShortcut(keyCode: 40, modifiers: UInt32(controlKey | shiftKey), keyLabel: "K")
        #expect(shortcut.isValid)
        #expect(shortcut.displayName == "⌃⇧K")
        let restored = try JSONDecoder().decode(GlobalShortcut.self, from: JSONEncoder().encode(shortcut))
        #expect(restored == shortcut)
        #expect(GlobalShortcut.defaultShortcut.isValid)
    }

    @Test func rejectsOrdinaryTypingAndModifierOnlyShortcuts() {
        #expect(!GlobalShortcut(keyCode: 0, modifiers: 0, keyLabel: "A").isValid)
        #expect(!GlobalShortcut(keyCode: 0, modifiers: UInt32(shiftKey), keyLabel: "A").isValid)
        #expect(!GlobalShortcut(keyCode: 58, modifiers: UInt32(optionKey), keyLabel: "Option").isValid)
        #expect(!GlobalShortcut(keyCode: 200, modifiers: UInt32(cmdKey), keyLabel: "Unknown").isValid)
        #expect(GlobalShortcut(keyCode: 122, modifiers: 0, keyLabel: "F1").isValid)
        #expect(GlobalShortcut(keyCode: 49, modifiers: UInt32(controlKey), keyLabel: "Space").isValid)
    }
}
