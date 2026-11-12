import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var preferences: Preferences
    @Bindable var model: PlaybackCoordinator
    @Bindable var hotkeys: HotkeyManager
    let panel: NotchPanelController
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("notchjam").font(.title2.weight(.semibold))
                        Text("peek at the lyrics. keep the groove.").foregroundStyle(.secondary)
                    }
                }
            }
            spotify
            shortcuts
            lyricsPanel
            Section("General") {
                Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Approve notchjam in System Settings → General → Login Items." : nil
                    } catch {
                        loginMessage = error.localizedDescription
                        loginEnabled = SMAppService.mainApp.status == .enabled
                    }
                }
                if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
            }
            demo
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .onAppear { hotkeys.configure(enabled: preferences.doubleOption) }
        .onDisappear { hotkeys.cancelRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            hotkeys.cancelRecording()
        }
    }

    private var spotify: some View {
        Section {
            LabeledContent {
                if !preferences.spotifyEnabled {
                    Button("Connect") { model.connectSpotify() }.buttonStyle(.borderedProminent)
                } else if model.automationDenied {
                    Button("Open Settings…") { openPrivacy("Automation") }
                } else {
                    Button("Reconnect") { model.connectSpotify() }
                }
            } label: {
                Text("Spotify")
                if !preferences.spotifyEnabled {
                    StatusLabel("Not connected", color: .secondary)
                } else if model.automationDenied {
                    StatusLabel("Access denied — allow notchjam under Automation", color: .orange)
                } else {
                    StatusLabel("Connected", color: .green)
                }
            }
        } header: {
            Text("Music")
        } footer: {
            Text("Song and position are read locally. Only title, artist, album and duration are sent to LRCLIB to find lyrics.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        Section {
            Toggle(isOn: $preferences.doubleOption) {
                Text("Double-tap left ⌥ Option")
                switch (preferences.doubleOption, hotkeys.optionStatus) {
                case (false, _): Text("Off")
                case (true, .active): StatusLabel("Active — tap left Option twice", color: .green)
                case (true, .needsPermission), (true, .off): StatusLabel("Needs Input Monitoring permission", color: .orange)
                case (true, .failed): StatusLabel("macOS refused the keyboard listener", color: .red)
                }
            }
            .onChange(of: preferences.doubleOption) { _, value in hotkeys.configure(enabled: value) }
            if preferences.doubleOption && hotkeys.optionStatus != .active {
                LabeledContent {
                    Button("Allow…") { hotkeys.configure(enabled: true, requestPermission: true) }
                } label: {
                    Text("Input Monitoring")
                    Text("Approve notchjam in System Settings. It turns on automatically — only Option key timing is read, never what you type.")
                }
                LabeledContent {
                    HStack {
                        Button("Reset") { hotkeys.resetPermission() }
                        Button("Restart notchjam") { relaunch() }
                    }
                } label: {
                    Text("Already allowed?")
                    Text("After a rebuild or update macOS may ignore the old approval. Reset asks again; some macOS versions also need a restart.")
                }
            }
            LabeledContent {
                ShortcutRecorder(preferences: preferences, hotkeys: hotkeys).fixedSize()
            } label: {
                Text("Keyboard shortcut")
                if let error = hotkeys.recordingError {
                    StatusLabel(error, color: .orange)
                } else if hotkeys.isRecording {
                    Text("Press keys with ⌘, ⌥ or ⌃, or an F-key. Esc cancels.")
                } else if !hotkeys.fallbackAvailable {
                    StatusLabel("Unavailable — record another shortcut", color: .orange)
                } else {
                    Text("Works everywhere, no permission needed. Click to change.")
                }
            }
        } header: {
            Text("Show lyrics with")
        }
    }

    private var lyricsPanel: some View {
        Section("Lyrics panel") {
            Picker("Hide the panel", selection: $preferences.toggleMode) {
                Text("When I press the shortcut again").tag(true)
                Text("Automatically").tag(false)
            }
            .onChange(of: preferences.toggleMode) { _, _ in panel.rescheduleDismissal() }
            if !preferences.toggleMode {
                Slider(value: $preferences.dismissal, in: 3...30, step: 1) {
                    Text("After \(Int(preferences.dismissal)) seconds")
                }
                .onChange(of: preferences.dismissal) { _, _ in panel.rescheduleDismissal() }
            }
            Slider(value: $preferences.textSize, in: 16...24, step: 1) {
                Text("Lyric size")
            } minimumValueLabel: {
                Text("A").font(.system(size: 11))
            } maximumValueLabel: {
                Text("A").font(.system(size: 17))
            }
            Toggle("Show song and artist", isOn: $preferences.showHeader)
            Toggle(isOn: $preferences.animations) {
                Text("Animations")
                Text("Always off when Reduce Motion is on.")
            }
        }
    }

    private var demo: some View {
        Section {
            Toggle(isOn: $preferences.mockPlayback) {
                Text("Demo playback")
                Text("A looping sample song, no Spotify needed. Resets when notchjam quits.")
            }
            .onChange(of: preferences.mockPlayback) { _, _ in model.restartSource() }
            if preferences.mockPlayback {
                HStack {
                    Button("Show Lyrics") { panel.show() }
                    Button(model.mockPaused ? "Resume" : "Pause") { model.mockTogglePause() }
                    Button("Skip 10 s") { model.mockSeek() }
                }
            }
        } header: {
            Text("Try it out")
        }
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) { NSWorkspace.shared.open(url) }
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

private struct StatusLabel: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color) { self.text = text; self.color = color }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}
