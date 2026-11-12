import AppKit
import SwiftUI

@main
struct NotchjamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = Preferences()
    private lazy var model = PlaybackCoordinator(preferences: preferences)
    private lazy var panel = NotchPanelController(model: model)
    private let hotkeys = HotkeyManager()
    private var statusItem: NSStatusItem?
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hotkeys.onToggle = { [weak self] in self?.panel.toggle() }
        hotkeys.start(shortcut: preferences.shortcut)
        hotkeys.configure(enabled: preferences.doubleOption)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "notchjam")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "notchjam — peek at the lyrics. keep the groove."
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        model.start()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        if preferences.mockPlayback { panel.show() }
        else if !UserDefaults.standard.bool(forKey: "hasOpened") {
            UserDefaults.standard.set(true, forKey: "hasOpened")
            showSettings()
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(model.visible ? "Hide Lyrics" : "Show Lyrics", action: #selector(toggle), to: menu)
        add(model.pinned ? "Unpin Lyrics" : "Pin Lyrics", action: #selector(pin), to: menu)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), key: ",", to: menu)
        menu.addItem(.separator())
        add("Quit notchjam", action: #selector(quit), key: "q", to: menu)
    }
    private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    @objc private func toggle() { panel.toggle() }
    @objc private func pin() { panel.togglePin() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screenChanged() { panel.position() }
    @objc private func spaceChanged() { if model.visible { panel.position() } }
    @objc private func becameActive() { hotkeys.configure(enabled: preferences.doubleOption) }
    @objc private func willSleep() { panel.hide(); model.sleep() }
    @objc private func didWake() { model.wake(); hotkeys.configure(enabled: preferences.doubleOption) }
    @objc private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "notchjam Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, model: model, hotkeys: hotkeys, panel: panel))
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.stop(); hotkeys.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
