<div align="center">
  <img src="Resources/AppIcon.png" width="90" alt="Still botanical clock icon">
  <h1>Still</h1>
  <p>A tiny, quiet macOS focus timer.</p>
</div>

## Out of your way

A native SwiftUI + AppKit companion that sits lightly above your desktop.
**128 × 52 points** by default. Just the countdown: clear minutes and smaller,
softer seconds on a translucent surface. No accounts, analytics, or network requests.

- **Click to expand.** Choose 25 or 50 minutes and the controls disappear again.
  Set another default duration in Preferences to add a custom shortcut.
- **Quiet while you work.** Click the desktop or press Esc to collapse. Hovering
  does not open anything. Drag the digits to move the timer.
- **Adjustable.** Resize the compact timer and change background opacity in Preferences.
- **Follows your Mac.** System light/dark mode by default, with manual overrides.
- **Your sessions, in Markdown.** Pick an existing `.md` file or a new path. Still
  appends completed focus sessions, preserving your notes and avoiding duplicates.
- **Gentle endings.** Local notifications and an original soft two-note chime.
- **Reliable timing.** Pause/resume, sleep/wake, and relaunch use absolute deadlines.
  Breaks and unfinished intervals never count as focus sessions.

## Build and run

macOS 14+ and Swift 6 (Xcode or Command Line Tools). No third-party dependencies.

```sh
git clone https://github.com/onjas-6/still-pomodoro.git
cd still-pomodoro
./scripts/build.sh
open build/Still.app
```

Open `Package.swift` in Xcode to develop. Run the bundled `.app` so macOS can identify
it for notifications. Builds are ad-hoc signed for local use. Public trusted binary
releases need Developer ID signing and notarization; set `CODE_SIGN_IDENTITY` to use
your own identity. `STILL_BUILD_PATH` optionally places build artifacts elsewhere.

## Use

1. Click the small countdown, then **25 min** or **50 min** to start.
2. Click it again to pause, continue, reset, start a break, or open preferences.
3. In Preferences, choose **System / Light / Dark**, timer size, and background opacity.
4. Under **Markdown journal**, enter a path and click **Save path**, or choose a file.
   Use **Open Markdown** to see the actual record in your editor.

After quitting Still, you can also set the path from a terminal:
`./build/Still.app/Contents/MacOS/Still --journal /path/to/focus-sessions.md`.

The menu-bar leaf can show or hide the timer, open history, or quit. Hidden timers
keep running. Quitting leaves an already-scheduled notification intact; a completed
session is reconciled on the next launch. Notifications and sounds respect macOS
Focus and notification settings; a sleeping Mac cannot play audio until wake/delivery.

## Your data

The default journal destination is `~/Documents/Still-sessions.md`. You can place
it anywhere writable, including your own notes folder. Existing Markdown content is
preserved. Each entry includes a readable local timestamp, timezone, duration, and
an invisible session identifier for reliable synchronization.

A small recovery cache at `~/Library/Application Support/Still/state.json` keeps the
active timer, preferences, and sessions so a failed Markdown write does not lose your
work. The app shows write errors and retries on launch or when the path is saved
again. Changing the journal path preserves existing contents and carries your session
history into the selected file. Keep hidden Still metadata comments if you edit the
journal, so the app can recognize entries and avoid duplicating them.

Window position lives in macOS app preferences. No data leaves your Mac through Still.
Any cloud synchronization is controlled by the folder you choose.

## Development

```sh
./scripts/test.sh                              # timer core, including CLT-only Macs
./scripts/test-journal.sh                      # Markdown preservation and round-trip checks
swift test                                    # XCTest, with full Xcode
./scripts/build.sh
./build/Still.app/Contents/MacOS/Still --self-test  # isolated persistence checks
```

- `Sources/StillCore` — timer state machine, sessions, Markdown journal.
- `Sources/Still` — compact panel, controls, preferences, notifications, recovery cache.
- `scripts/generate-assets.swift` — reproducible original icon and chime.

Tests use temporary data. To regenerate assets, run `swift scripts/generate-assets.swift`.

## License

[MIT](LICENSE). Made by [Jason Hu](https://github.com/onjas-6).
