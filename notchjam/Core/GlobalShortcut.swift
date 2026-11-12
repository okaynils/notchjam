import Foundation
import Carbon

struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultShortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | optionKey), keyLabel: "L")
    static let functionKeys: [UInt32: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]

    var isValid: Bool {
        let allowed = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        guard keyCode < 128, !(54...63).contains(keyCode), !keyLabel.isEmpty,
              modifiers & ~allowed == 0 else { return false }
        return modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 || Self.functionKeys[keyCode] != nil
    }

    var displayName: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyLabel
    }
}

enum PanelDismissal {
    static func delay(visible: Bool, pinned: Bool, toggleMode: Bool, duration: Double) -> Double? {
        visible && !pinned && !toggleMode ? duration : nil
    }
}
