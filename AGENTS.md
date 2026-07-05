# NoDoze Agent Notes

## Project Shape

- This is a deliberately small Swift/AppKit macOS app.
- Keep application code in Swift. Avoid adding Python, Node, or other helper runtimes for app behavior.
- The packaged app is built manually from the SwiftPM release binary, `Info.plist`, and `Resources/NoDoze.icns`.

## Build

From the repository root:

```sh
swift build -c release
mkdir -p dist/NoDoze.app/Contents/MacOS dist/NoDoze.app/Contents/Resources
cp .build/release/NoDoze dist/NoDoze.app/Contents/MacOS/NoDoze
cp Info.plist dist/NoDoze.app/Contents/Info.plist
cp Resources/NoDoze.icns dist/NoDoze.app/Contents/Resources/NoDoze.icns
chmod +x dist/NoDoze.app/Contents/MacOS/NoDoze
codesign --force --deep --sign - dist/NoDoze.app
codesign --verify --deep --strict dist/NoDoze.app
```

## Review Guidelines

- Verify that Start and Stop remain symmetric: `caffeinate` must be terminated and the previous screen saver idle setting must be restored on Stop and app quit.
- Keep `dist/`, `.build/`, and Finder metadata out of commits.
- Be careful with macOS preference writes. Changes should stay scoped to the current user's current-host screen saver idle timer.
