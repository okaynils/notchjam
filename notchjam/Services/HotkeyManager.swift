import AppKit
import Carbon
import Observation

@MainActor @Observable
final class HotkeyManager {
    enum OptionTapStatus: Equatable { case off, needsPermission, active, failed }
    private(set) var optionStatus = OptionTapStatus.off
    private(set) var fallbackAvailable = false
    private(set) var isRecording = false
    private(set) var recordingError: String?
    private var configuredShortcut = GlobalShortcut.defaultShortcut
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var recognizer = OptionTapRecognizer()
    private var permissionPoll: Task<Void, Never>?
    var onToggle: (() -> Void)?

    func start(shortcut: GlobalShortcut = .defaultShortcut) {
        configuredShortcut = shortcut
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
                if !manager.isRecording { manager.onToggle?() }
            }
            return noErr
        }, 1, &type, pointer, &handler)
        if status == noErr { registerShortcut(shortcut) }
    }

    @discardableResult private func registerShortcut(_ shortcut: GlobalShortcut) -> Bool {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil
        let id = EventHotKeyID(signature: 0x4e4a414d, id: 1)
        fallbackAvailable = handler != nil && shortcut.isValid &&
            RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                GetApplicationEventTarget(), 0, &hotkey) == noErr
        return fallbackAvailable
    }

    func beginRecording() {
        isRecording = true
        recordingError = nil
        recognizer.cancel()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil
        fallbackAvailable = false
    }

    func saveRecording(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else {
            recordingError = "Include Command, Option, or Control, or choose an F-key."
            return false
        }
        guard registerShortcut(shortcut) else {
            recordingError = "That shortcut is unavailable. Try another combination."
            return false
        }
        configuredShortcut = shortcut
        isRecording = false
        recordingError = nil
        return true
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingError = nil
        registerShortcut(configuredShortcut)
    }

    /// Permission is requested only after the user chooses Enable in Preferences.
    func configure(enabled: Bool, requestPermission: Bool = false) {
        stopMonitoring()
        guard enabled else { permissionPoll?.cancel(); optionStatus = .off; return }
        var allowed = CGPreflightListenEventAccess()
        if !allowed && requestPermission { allowed = CGRequestListenEventAccess() }
        guard allowed else {
            optionStatus = .needsPermission
            if requestPermission { waitForPermission() }
            return
        }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue) |
                   (CGEventMask(1) << CGEventType.keyDown.rawValue) |
                   (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) |
                   (CGEventMask(1) << CGEventType.rightMouseDown.rawValue) |
                   (CGEventMask(1) << CGEventType.otherMouseDown.rawValue) |
                   (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                               eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue().receive(type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { optionStatus = .failed; return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        permissionPoll?.cancel()
        optionStatus = .active
    }

    /// Starts listening as soon as the user approves notchjam in System Settings, without a relaunch.
    private func waitForPermission() {
        permissionPoll?.cancel()
        permissionPoll = Task { [weak self] in
            for _ in 0..<180 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard CGPreflightListenEventAccess() else { continue }
                self?.configure(enabled: true)
                return
            }
        }
    }

    /// Ad-hoc signed builds get a new code signature on every rebuild, which silently invalidates an
    /// existing Input Monitoring approval while System Settings still shows it as enabled.
    func resetPermission() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "ListenEvent", Bundle.main.bundleIdentifier ?? "com.notchjam.app"]
        try? reset.run()
        reset.waitUntilExit()
        configure(enabled: true, requestPermission: true)
    }

    private func receive(_ type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recognizer.cancel()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard !isRecording else { recognizer.cancel(); return }
        guard type == .flagsChanged else { recognizer.cancel(); return }
        let flags = event.flags
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        // NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK (public IOKit event flags).
        let leftDown = flags.rawValue & 0x20 != 0
        let rightDown = flags.rawValue & 0x40 != 0
        let others = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskSecondaryFn]).rawValue != 0 || rightDown
        guard code == Int64(kVK_Option) else { recognizer.cancel(); return }
        // CGEvent timestamps are mach ticks on Apple Silicon, not nanoseconds; NSEvent converts to seconds.
        let time = NSEvent(cgEvent: event)?.timestamp ?? ProcessInfo.processInfo.systemUptime
        if recognizer.keyChanged(leftOptionDown: leftDown, otherModifiers: others, at: time) {
            // Leave the event tap callback before touching windows.
            DispatchQueue.main.async { [weak self] in self?.onToggle?() }
        }
    }
    private func stopMonitoring() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
        recognizer.cancel()
    }
    func stop() {
        stopMonitoring()
        permissionPoll?.cancel()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
        hotkey = nil; handler = nil
    }
}
