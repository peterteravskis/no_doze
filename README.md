# NoDoze

![NoDoze app icon](Sources/NoDoze.png)

NoDoze is a tiny Swift-only macOS app for keeping your Mac awake during AI agent computer use, browser automation, desktop automation, long-running local coding agents, and other unattended workflows.

It is basically a friendly one-button GUI for `caffeinate`, with a few extra practical touches for AI agents: it also disables the screen saver while running, can stop itself on a timer or at a wall-clock time, then restores your previous screen saver behavior when stopped.

## Why This Exists

AI coding agents and computer-use agents often need a Mac to stay awake while they read files, control apps, run tests, use a browser, or wait on long builds. If the display sleeps, the screen saver starts, or the session locks, desktop automation can stall.

NoDoze is meant for those moments:

- keep a Mac awake for AI agent computer use
- prevent sleep during Codex, local coding agent, or automation sessions
- prevent the macOS screen saver from interrupting desktop automation
- run `caffeinate` from a simple Start/Stop app instead of a Terminal window
- set an optional stop timer or wall-clock stop before starting
- control NoDoze from the menu bar after closing the window
- restore the previous screen saver setting when you stop or quit

## Behavior

Start:
- launches `/usr/bin/caffeinate -dimsu -w <app-pid>`
- disables the current-host screen saver idle timer
- arms the optional stop timer and wall-clock stop, if enabled

Stop, automatic stop, or quit:
- terminates `caffeinate`
- restores the previous screen saver idle timer

## Build

```sh
swift build -c release
mkdir -p dist/NoDoze.app/Contents/MacOS
mkdir -p dist/NoDoze.app/Contents/Resources
cp .build/release/NoDoze dist/NoDoze.app/Contents/MacOS/NoDoze
cp Info.plist dist/NoDoze.app/Contents/Info.plist
cp Resources/NoDoze.icns dist/NoDoze.app/Contents/Resources/NoDoze.icns
chmod +x dist/NoDoze.app/Contents/MacOS/NoDoze
codesign --force --deep --sign - dist/NoDoze.app
codesign --verify --deep --strict dist/NoDoze.app
```

## Open

```sh
open dist/NoDoze.app
```

## Notes

- This app changes only the current user's current-host screen saver idle timer.
- NoDoze stores the previous screen saver idle setting before starting and restores it on Stop or quit.
- The `-w <app-pid>` guard means `caffeinate` should not survive the app process.
- The packaged `.app` in `dist/` is ignored by git. Rebuild it locally when needed.

## Privacy

NoDoze has no telemetry, no analytics, no network calls, and no background service. It only starts `/usr/bin/caffeinate` and temporarily changes the current-host screen saver idle timer while running.

## License

MIT

## Search Terms

macOS keep awake app, Mac caffeinate GUI, prevent Mac sleep, disable screen saver temporarily, AI agent computer use, Codex computer use, local coding agent, desktop automation, browser automation, unattended Mac automation.
