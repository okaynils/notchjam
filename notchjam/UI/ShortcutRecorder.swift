import AppKit
import SwiftUI
import Carbon

struct ShortcutRecorder: NSViewRepresentable {
    let preferences: Preferences
    let hotkeys: HotkeyManager

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(RecorderButton.begin)
        button.onBegin = { hotkeys.beginRecording() }
        button.onCancel = { hotkeys.cancelRecording() }
        button.onRecord = { shortcut in
            guard hotkeys.saveRecording(shortcut) else { return false }
            preferences.shortcut = shortcut
            return true
        }
        button.setAccessibilityLabel("Record lyrics keyboard shortcut")
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.recording = hotkeys.isRecording
        button.title = hotkeys.isRecording ? "Type shortcut…" : preferences.shortcut.displayName
    }

    final class RecorderButton: NSButton {
        var recording = false
        var onBegin: (() -> Void)?
        var onCancel: (() -> Void)?
        var onRecord: ((GlobalShortcut) -> Bool)?
        override var acceptsFirstResponder: Bool { true }

        @objc func begin() {
            window?.makeFirstResponder(self)
            recording = true
            onBegin?()
        }
        override func resignFirstResponder() -> Bool {
            if recording { recording = false; onCancel?() }
            return super.resignFirstResponder()
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            guard !event.isARepeat else { return }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
                recording = false
                onCancel?()
                return
            }
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            let code = UInt32(event.keyCode)
            let special: [UInt32: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
                76: "⌤", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home",
                119: "End", 116: "Page Up", 121: "Page Down"]
            let label = GlobalShortcut.functionKeys[code] ?? special[code] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
            if onRecord?(GlobalShortcut(keyCode: code, modifiers: modifiers, keyLabel: label)) == true {
                recording = false
            }
        }
    }
}
