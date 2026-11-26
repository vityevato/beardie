---
name: beardie-ui-testing
description: Use when writing or running Beardie UI tests (BeardieUITests), capturing Preferences/Shortcuts screenshots, or changing UI that the tests cover.
---

# Beardie UI tests

## Layout

- `BeardieUITests/` — XCUITest target.
- `BeardieUITests` — shared scheme; UI tests are intentionally not part of the normal unit-test scheme or CI.
- `BeardieUITestCase.swift` — deterministic launch arguments, opening Preferences through the status bar item, selecting the Shortcuts tab, screenshot and failure diagnostics.
- `ShortcutsPreferencesUITests.swift` — smoke test for the nine shortcut recorders, a record/clear test for `Play/Pause`, two Tab-navigation tests (keyboard navigation off/on), and the Shortcuts-pane screenshot capture.

## Running

UI tests need an unlocked GUI session. Smoke/capture/record tests can run with an unsigned local build. The Tab-navigation test additionally needs the **signed** app and a valid Accessibility permission for it, because Beardie uses a small CGEventTap to intercept Tab/Shift-Tab before `RecorderCocoa`'s local monitors.

Run selectively, never a whole UI plan.

Unsigned smoke/capture/record tests:

```sh
TEST_RUNNER_UI_SCREENSHOT_DIR="$PWD/.tmp/ui-screenshots/raw" \
xcodebuild test -workspace Beardie.xcworkspace -scheme BeardieUITests \
  -configuration Debug -destination 'platform=OS X,arch=arm64' \
  -derivedDataPath .tmp/ui-tests/DerivedData \
  -only-testing:BeardieUITests/ShortcutsPreferencesUITests/testShortcutsPaneShowsAllRecorders \
  CODE_SIGNING_ALLOWED=NO \
  GCC_PRECOMPILE_PREFIX_HEADER=NO \
  SWIFT_PRECOMPILE_BRIDGING_HEADER=NO
```

Signed Tab-navigation test:

```sh
xcodebuild test -workspace Beardie.xcworkspace -scheme BeardieUITests \
  -configuration Debug -destination 'platform=OS X,arch=arm64' \
  -derivedDataPath DerivedData \
  -only-testing:BeardieUITests/ShortcutsPreferencesUITests/testTabNavigation \
  GCC_PRECOMPILE_PREFIX_HEADER=NO \
  SWIFT_PRECOMPILE_BRIDGING_HEADER=NO
```

Why the flags:

- `CODE_SIGNING_ALLOWED=NO` — local Debug builds are unsigned; the UI test runner still launches the app.
- `GCC_PRECOMPILE_PREFIX_HEADER=NO` and `SWIFT_PRECOMPILE_BRIDGING_HEADER=NO` — `ConfigConstants.h` is generated during the build and otherwise produces `ConfigConstants.h has been modified since the precompiled header` errors. If that error appears, remove the DerivedData `.pch` files and rerun with these flags.
- `TEST_RUNNER_UI_SCREENSHOT_DIR` — makes an unsigned runner write screenshots to `.tmp/ui-screenshots/raw` instead of its temporary directory. A signed runner is sandboxed: it writes to its container, and `collect_ui_screenshots.sh` finds that container. The Tab test is normally run without this variable.

## Screenshots

The capture test saves `shortcuts-pane.png` into `UI_SCREENSHOT_DIR` (unsigned runner) or the runner container (signed runner). Collect it into the repository:

```sh
Scripts/collect_ui_screenshots.sh before
# or after
Scripts/collect_ui_screenshots.sh after
```

The result is in `.tmp/ui-screenshots/<subfolder>/`. The collector copies regular capture PNGs and ignores stale `failure-*` artifacts from earlier runs; failure diagnostics stay in the runner container/temp for inspection. Screenshots are for inspecting layout, clipping, labels, focus and visual state. They are **not** a pixel-perfect acceptance test: a new control may look different by design, and that is allowed.

A pixel diff is an optional diagnostic:

```sh
Scripts/diff_ui_screenshots.py \
  .tmp/ui-screenshots/before/shortcuts-pane.png \
  .tmp/ui-screenshots/after/shortcuts-pane.png
```

It exits 0 for identical images and 1 for a pixel difference. Treat the result as information, not as a pass/fail criterion. Check the before/after images for:

- grid alignment and control sizes;
- clipped or overlapping labels;
- the shortcut text and clear button;
- focus/recording state;
- light and dark appearance.

The historical MASShortcut baseline is `.tmp/ui-screenshots/before/shortcuts-pane.png`; it is a layout reference, not a target to match pixel-for-pixel. The current `RecorderCocoa` UI is in `.tmp/ui-screenshots/after/shortcuts-pane.png`.

## Accessibility identifiers

The Shortcuts recorders expose stable identifiers:

- `shortcut.playPause`
- `shortcut.nextTrack`
- `shortcut.previousTrack`
- `shortcut.setActiveTab`
- `shortcut.favorite`
- `shortcut.notification`
- `shortcut.activatePlayingTab`
- `shortcut.playerNext`
- `shortcut.playerPrevious`

The status item is `statusItem`, and the status-menu Preferences item is `menu.preferences`. Keep these identifiers stable; update the UI tests when a control is intentionally renamed.

## Notes

- Beardie is an accessory application (`LSUIElement`); Preferences are opened through the status bar item, not the main menu.
- UI tests are local only. Do not add them to CI.
- The `Play/Pause` record/clear test uses synthesized key events into the recorder and passes locally. If it becomes flaky, check focus first; the recorder must be first responder.
- The Tab tests read the focused control from `app.debugDescription` (`Keyboard Focused` plus `identifier: 'shortcut.*'`). The order is: Player Control Shortcuts (Play/Pause, Next, Previous) → Players Switching Shortcuts (Next, Previous) → Set Active Player Window → Raise/Hide Active Player Window → Toggle Favorite → Show Track Info.
- When macOS “Keyboard navigation” is **off** (`AppleKeyboardUIMode=0`, `NSApp.isFullKeyboardAccessEnabled == false`), Tab/Shift-Tab only move inside the recorder loop and wrap: last → first and first → last. They do **not** jump to the toolbar; the toolbar is treated as if it did not exist. This is what `testTabNavigation` checks.
- When keyboard navigation is **on**, Tab from the last recorder goes to the **first toolbar button** (General), Shift-Tab from the first goes to the **last toolbar button** (Controllers). This is what `testTabNavigationWithFullKeyboardAccess` checks.
- The tests force the mode with the test-only launch argument `-BSForceFullKeyboardAccess NO|YES`, so they do not depend on or change the user's system setting. In normal builds the app uses `NSApp.isFullKeyboardAccessEnabled`.
- The toolbar exit is explicit (`makeFirstResponder:`) because `RecorderCocoa` consumes Tab and the recorder fields are not naturally linked to the toolbar in AppKit's key-view loop. When keyboard navigation is off, that explicit toolbar path is not used at all.
- If explicit toolbar focus fails while keyboard navigation is on, the code falls back to `selectNextKeyView:`/`selectPreviousKeyView:`; this is a safety net for future macOS changes.
- The Tab test and the app's Tab event tap need the **signed** app with Accessibility permission. Do not add `CODE_SIGNING_ALLOWED=NO` to the Tab test command; otherwise the event tap cannot be created and Shift-Tab may fall back to the unreliable `RecorderCocoa` local monitors.
- The Tab test takes about 1.5–2 minutes because it walks all nine recorders in both directions.
- `testRecordsAndClearsPlayPauseShortcut` records F19 with no modifier flags, then clears it. Using a no-modifier function key avoids leaving Command/Option/Control flags in the test runner, which previously leaked into the following Tab test and recorded Control-Tab into the next recorder.
- A global hotkey press cannot be synthesized by the test runner on this machine: `CGPreflightPostEventAccess()` is `false`. Verify actual global triggering manually, or grant the runner Accessibility/Input Monitoring and add a separate test.
- The base launch arguments include `-SonosSupport NO` to avoid the system local-network permission prompt while capturing screenshots.
- The test base class saves a full-screen screenshot and the accessibility hierarchy on assertion failures into the same screenshot directory. Warnings and performance issues do not create failure artifacts.
