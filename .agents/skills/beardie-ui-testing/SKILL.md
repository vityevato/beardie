---
name: beardie-ui-testing
description: Use when writing or running Beardie UI tests (BeardieUITests), capturing Preferences/Shortcuts screenshots, or changing UI that the tests cover.
---

# Beardie UI tests

## Layout

- `BeardieUITests/` — XCUITest target.
- `BeardieUITests` — shared scheme; UI tests are intentionally not part of the normal unit-test scheme or CI.
- `BeardieUITestCase.swift` — deterministic launch arguments, opening Preferences through the status bar item, selecting the Shortcuts tab, screenshot and failure diagnostics.
- `ShortcutsPreferencesUITests.swift` — smoke test for the nine shortcut recorders and the Shortcuts-pane screenshot capture.

## Running

UI tests need an unlocked GUI session. The first run may ask for Accessibility permission for `BeardieUITests-Runner`.

Run selectively, never a whole UI plan:

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

Why the flags:

- `CODE_SIGNING_ALLOWED=NO` — local Debug builds are unsigned; the UI test runner still launches the app.
- `GCC_PRECOMPILE_PREFIX_HEADER=NO` and `SWIFT_PRECOMPILE_BRIDGING_HEADER=NO` — `ConfigConstants.h` is generated during the build and otherwise produces `ConfigConstants.h has been modified since the precompiled header` errors. If that error appears, remove the DerivedData `.pch` files and rerun with these flags.
- `TEST_RUNNER_UI_SCREENSHOT_DIR` — makes the runner write screenshots to `.tmp/ui-screenshots/raw` instead of its temporary directory, which may be cleaned on exit.

## Screenshots

The capture test saves `shortcuts-pane.png` into `UI_SCREENSHOT_DIR` (or the runner temp directory when the variable is not set). Collect it into the repository:

```sh
Scripts/collect_ui_screenshots.sh before
# or after
Scripts/collect_ui_screenshots.sh after
```

The result is in `.tmp/ui-screenshots/<subfolder>/`. Screenshots are for inspecting layout, clipping, labels, focus and visual state. They are **not** a pixel-perfect acceptance test: a new control may look different by design, and that is allowed.

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

The baseline for the current MASShortcut UI is `.tmp/ui-screenshots/before/shortcuts-pane.png`; it is a layout reference, not a target to match pixel-for-pixel.

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
- Synthesized keyboard input into recorder/search fields may be unreliable. Prefer checking existence, layout, focus and screenshots; use a debug hook for value changes when necessary.
- The test base class saves a full-screen screenshot and the accessibility hierarchy on failure into the same screenshot directory.
