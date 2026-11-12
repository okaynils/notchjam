import AppKit
import SwiftUI

final class LyricsPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController {
    private let panel: LyricsPanel
    private let model: PlaybackCoordinator
    private var dismissalTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var currentScreen: NSScreen?

    init(model: PlaybackCoordinator) {
        self.model = model
        panel = LyricsPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.setAccessibilityLabel("notchjam lyrics")
        let host = NSHostingView(rootView: LyricsView(model: model, onPin: { [weak self] in self?.togglePin() },
                                                     onClose: { [weak self] in self?.hide() }))
        // position() owns the frame and LyricsView applies notchInset itself. If SwiftUI also resizes the window or
        // reacts to the notch safe area mid-layout, AppKit raises an exception, so the host sits in a plain container.
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.autoresizingMask = [.width, .height]
        let container = NSView()
        container.addSubview(host)
        panel.contentView = container
    }
    private var animated: Bool {
        model.preferences.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    func toggle() { model.visible ? hide() : show() }
    func show() {
        hideTask?.cancel()
        currentScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        position()
        panel.orderFrontRegardless() // Deliberately never makeKey, activate, or change the first responder.
        model.setVisible(true)
        withAnimation(animated ? .spring(response: 0.34, dampingFraction: 0.9) : nil) { model.expanded = true }
        rescheduleDismissal()
    }
    func hide() {
        dismissalTask?.cancel()
        hideTask?.cancel()
        model.pinned = false
        model.setVisible(false)
        withAnimation(animated ? .easeInOut(duration: 0.2) : nil) { model.expanded = false }
        let delay = animated ? 0.21 : 0
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !self.model.visible else { return }
            self.panel.orderOut(nil)
        }
    }
    func togglePin() {
        model.pinned.toggle()
        if !model.visible { show() } else { rescheduleDismissal() }
    }
    func rescheduleDismissal() {
        dismissalTask?.cancel()
        guard let seconds = PanelDismissal.delay(visible: model.visible, pinned: model.pinned,
                                                toggleMode: model.preferences.toggleMode,
                                                duration: model.preferences.dismissal) else { return }
        dismissalTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.hide()
        }
    }
    func position() {
        let screens = NSScreen.screens
        let screen = currentScreen.flatMap { old in screens.first { $0 == old } } ?? NSScreen.main ?? screens.first
        guard let screen else { hide(); return }
        currentScreen = screen
        let hasNotch = screen.safeAreaInsets.top > 0 && screen.auxiliaryTopLeftArea != nil
        let inset = hasNotch ? screen.safeAreaInsets.top : 0
        model.notchInset = inset
        let width = min(440.0, screen.frame.width - 32)
        let height = 248.0 + inset
        let top = hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - 8
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height), display: true)
    }
}
