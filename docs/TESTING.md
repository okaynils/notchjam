# Verification

Verified on 2026-11-12 with Xcode 27.2 / Swift 6.4.2, Apple Silicon, deployment target macOS 14.

## Results actually observed

- Xcode **Debug build succeeded**.
- Xcode **Release build succeeded**; local ad-hoc code signature verification succeeded.
- **18 Swift Testing tests in 6 suites passed** through Swift Package Manager. One parameterized test executes six lookup/cache cases.
- The Xcode test bundle compiled and linked, but hosted execution failed because this environment denies `com.apple.testmanagerd.control` (sandbox error 159). This is not recorded as a passing Xcode test run.
- The runtime AppleScript compiled with `osacompile`. Spotify’s installed scripting dictionary was inspected for property and enumeration codes. Actual Spotify Apple Event reads were not verified.
- Info.plist, entitlements, and project file passed `plutil -lint`.
- The app opened through desktop automation; its menu and Preferences accessibility tree were inspected and demo playback was enabled. The later Peek inspection lost its app connection; a Release inspection timed out. Full desktop overlay behavior is therefore **not verified**.
- The actual SwiftUI lyrics view was compiled into an offscreen render harness, rendered successfully, and visually inspected. The sample is `docs/panel.png`. This verifies static layout, not window placement or animation behavior.
- Live LRCLIB access from the execution shell was blocked by DNS/network restrictions. API behavior was tested through URLProtocol fixtures; implementation was checked against the current public LRCLIB documentation.

The shortcut update adds tests for toggle/timed dismissal, shortcut serialization, supported modifier combinations, F-keys, and rejection of ordinary typing or modifier-only shortcuts. Interactive recording/global registration still needs the desktop checks below.

The initial tests found a duplicate-translation timestamp bug. It was fixed and the full suite rerun successfully.

## Restricted-environment commands

The build environment denies the compiler plugin subprocess’s nested sandbox and writes to user-wide compiler caches. These invocation-only options were used; they are not embedded in the application’s build settings or entitlements:

```sh
xcodebuild -project notchjam.xcodeproj -scheme notchjam \
  -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' build

CLANG_MODULE_CACHE_PATH=/tmp/notchjam-module-cache \
  swift test --disable-sandbox --cache-path /tmp/notchjam-spm-cache \
  --scratch-path /tmp/notchjam-swift-build \
  -Xswiftc -Xfrontend -Xswiftc -disable-sandbox
```

A direct GUI launch from the sandbox aborted in macOS application registration before app initialization; LaunchServices also returned `kLSNoExecutableErr` despite the executable being present and signed. Desktop automation opened the app separately, but did not remain reliable enough for the full acceptance pass.

## Desktop acceptance checklist

Run these on a normal, signed local installation before distributing:

- [ ] Connect Spotify and approve Automation; verify title, artist, album, playback state and position against Spotify.
- [ ] Deny Automation once: see a helpful state, no background prompts, and successful explicit reconnect after allowing it.
- [ ] Quit Spotify; show the panel and confirm it does not launch Spotify. Open Spotify and confirm automatic recovery.
- [ ] Play a track with known synchronized LRCLIB lyrics; verify progression, pause, resume, seek forward/backward and rapid skips.
- [ ] Disconnect networking: cached tracks still work; uncached tracks show an error and recover on retry. Test missing and plain-only lyrics.
- [ ] With a text editor focused, use ⌘⌥L and double-left-Option. Type immediately afterward; input must remain in the editor.
- [ ] Verify right Option, slow taps, held Option, Option+letter, and Option+click do not toggle the panel. Verify Input Monitoring denial does not break the menu or conventional fallback.
- [ ] Confirm default toggle mode stays open beyond the selected Quick Peek duration and closes on the next shortcut. Disable toggle mode and confirm timed dismissal. Change modes while visible to verify the timer is canceled/restarted.
- [ ] Record a custom shortcut, verify it replaces the previous one, and relaunch to confirm persistence. Test cancellation with Escape, loss of focus, and closing Preferences; the saved shortcut must be restored. A conflicting registration must show an error without saving the new combination.
- [ ] Confirm repeated toggles do not cause a stuck overlay, pin survives the timer, and unpin restarts it only with toggle mode disabled.
- [ ] Verify pin/close/scroll clicks do not activate notchjam. Open Preferences deliberately and confirm it can receive focus normally.
- [ ] Test a notched laptop, non-notched screen, external monitor connection/removal, different scaling factors, Spaces and full-screen apps.
- [ ] Sleep while pinned, then wake; overlay should be dismissed and playback should resynchronize.
- [ ] Check Reduce Motion, disabled animations, small/large text, long lyrics, Unicode, light/dark appearance and VoiceOver labels.
- [ ] Relaunch: preferences persist, demo mode and pinned state do not. Test launch-at-login after installing to Applications.
- [ ] Profile CPU/energy while hidden, visible, paused, and Spotify closed; verify no polling or lyric ticker while asleep.
