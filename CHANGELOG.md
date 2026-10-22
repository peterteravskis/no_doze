# Changelog

## 1.2

Fixes a gap in activity protection on macOS 27: NoDoze could show Running after the user-activity assertion created by `caffeinate -u` had expired. NoDoze now declares activity through IOKit immediately and renews it every 15 seconds for the duration of the session. The existing display and system sleep assertions and temporary screen saver preference remain in place.

- Release the activity assertion and cancel renewal on Stop, automatic stop, quit, or unexpected `caffeinate` exit.
- Stop the session and report an error if activity creation or renewal fails.
- Ignore delayed termination callbacks from previous `caffeinate` processes during rapid Stop/Start.
- Allow automatic stop timers and activity renewal to fire while tracking menus or dials.
- Read the latest current-host screen saver preference before saving its restoration value.
- Expose custom dial and switch controls to Accessibility and implement their actions.
- Add tests covering renewal, failure cleanup, process lifetime, and screen saver recovery.

Requires macOS 13 or later. The local release package is built for Apple silicon.
