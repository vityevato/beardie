# Now Playing browser players and Raise/Hide (Stage 3)

- Date: 2026-11-28.
- Stage: 3 of the `beardie-nowplaying-transition-plan`.
- Scope: make tabs reported by the Stage 2 browser bridge first-class players in
  the existing player selection, and use the existing **Raise/Hide Active
  Player Window** shortcut on the selected tab, whether it is playing or
  paused.
- The legacy web-strategy bridge, the legacy extensions and media command
  routing stay unchanged until Stages 4 and 6.

## Core rule: selection first, matching second

Stage 3 does not introduce a second player selector. The app already has one:

- `autoSelectTabWithForceFocused:` decides the current player before every
  action:
  - exactly one playing player → it;
  - otherwise the frontmost player;
  - otherwise the current `activeTab`;
  - otherwise the player selected in the menu.
- `BSActiveTab` stores that choice in `activeApp.activeTab` and performs the
  action.

`isPlaying` is a signal for **selection**. It is not a condition for Raise/Hide.
Once the mechanism has selected a browser tab, the shortcut must raise and
restore it even if it is paused.

`BrowserTargetResolver` is a matcher, not a selector. It associates a
`NowPlayingClient` with a bridge tab by bundle and metadata, and it never
filters clients by `isPlaying` and never overrides `activeApp.activeTab`. Stage 4
uses it for command routing; Raise/Hide works from the selected `TabAdapter`.

## Stage 4 command routing

`CommandRouter` sits between the existing selection and the transports. It
receives `BSActiveTab` after `autoSelectTabWithForceFocused:` has already
chosen the player and returns `true` only when it delivered the command.
Otherwise the caller runs the legacy adapter method.

| Selected player | toggle | next / previous | favorite | volume |
|---|---|---|---|---|
| `BrowserBridgeTabAdapter` | bridge `command` (`toggle`) | bridge `next` / `previous` via the Media Session shim; MediaRemote fallback | MediaRemote `LikeTrack` only | legacy |
| native application | targeted MediaRemote `TogglePlayPause` (or `Play`/`Pause`) | targeted `NextTrack` / `PreviousTrack` | targeted `LikeTrack` | legacy |
| Sonos / legacy web | legacy adapter | legacy adapter | legacy adapter | legacy |

Routing conditions:

- targeted MediaRemote commands require `UseSystemNowPlaying`, healthy XPC, a
  matching client and an enabled supported command;
- bridge commands require `UseBrowserBridge` and a connected instance;
- the router never changes `activeApp.activeTab` and never asks
  `autoSelectTabWithForceFocused:` to select again;
- MediaRemote command numbers are taken from the client's reported
  `supportedCommands` when available (for example `LikeTrack = 21` on macOS
  27.2.1).

The command UI does not change. The status menu keeps only the player list and
the existing application items; commands are triggered by hotkeys and media
keys. Capability checks are internal to the router: they decide whether a
targeted MediaRemote command can be used or the legacy adapter path must run.

`pauseOthers` is exposed by `ElectionController` and `CommandRouter`; it pauses
every other playing MediaRemote client through separate transactions. No UI
trigger is added in Stage 4; Stage 5 uses it when native adapters are removed.

## Bridge tabs as players

`BrowserBridgeTabAdapter` is a `TabAdapter` for one `instanceId#tabId`:

- `title`, `URL`, `key`, `trackInfo` come from the bridge tab;
- `isPlaying` comes from `playbackState`;
- `frontmost` is true when the browser is the frontmost application and the
  tab is its active tab;
- `toggleTab` raises the tab on the first call and restores the previously
  active tab on the next call;
- `pause`, `next`, `previous`, `favorite` and volume are not routed in this
  stage.

`NowPlayingBrowserTabs` builds and caches adapters from
`BrowserBridgeService.activeInstances` on every `refreshTabs` call. Cached
identity keeps `BSActiveTab` and the raise state stable across menu refreshes.
Tabs without media metadata are not exposed.

`AppDelegate.refreshTabs` and `setActiveTabShortcut` include these adapters next
to legacy web tabs, native apps and Sonos rooms, so they appear in the status
menu and participate in the normal frontmost/menu selection.

`activatePlayingTab` is back to the existing path:

```text
autoSelectTabWithForceFocused:NO
  → activeApp.activeTab (bridge adapter or legacy adapter)
  → activatePlayingTab
  → toggleTab
```

There is no separate `NowPlayingBrowserTargets.toggle` selection path anymore.

## Raise/Hide lifecycle

The adapter keeps a per-tab raised flag:

1. First shortcut press sends `activateTab` with a generated `requestId`.
2. The extension records the tab that was active in the target window before
   the activation and focuses the target tab and window.
3. A successful `ack` marks the tab as raised.
4. The next shortcut press sends `restoreTab`; the extension switches back to
   the recorded tab and focuses its window.
5. A failed or timed-out restore is treated as handled best effort and clears
   the raised flag.

`BrowserBridgeService` resolves `ack` by `requestId`, enforces a 3-second
timeout, fails pending requests on instance disconnect or service stop, and
delivers completions on the main queue. Requests arriving after a timeout are
ignored.

## Gating

Raise/Hide for browser tabs depends only on `UseBrowserBridge`, because the
bridge already reports playback state. `UseSystemNowPlaying` is not required for
this path; it stays the gate for the read-only MediaRemote snapshot and future
command routing.

When `UseBrowserBridge` is off, no bridge tabs exist, and the app behaves
exactly as before.

## Verification

- `BeardieTests`: 38 tests pass, including:
  - `BrowserTargetResolverTests`: paused player resolves, playing/paused
    selection, bundle/helper matching, conflicting artist, ambiguous metadata,
    stale data, paused tab state;
  - `BrowserBridgeTests`: `activateTab` / `restoreTab` encoding and hello/state
    parsing.
- Debug and Release builds of `Beardie` succeed.
- Chromium 138.0.7204.49 E2E with a custom profile and the packaged
  `Beardie-NowPlaying.chrome` (`UseBrowserBridge` only):
  - bridge `state` reported one media tab and one blank tab;
  - paused media tab selected through `updateActiveTab:` (the same path as the
    menu) was raised with `BrowserBridgeTabAdapter: raise tab` and restored on
    the next invocation;
  - playing media tab was selected by `autoSelectTabWithForceFocused` and
    raised/restored the same way;
  - `chrome.tabs.query` confirmed the active tab changed to the media tab and
    back to the blank tab;
  - `BSActiveTab.displayName` returned `Chromium` for the bridge adapter.
- Stage 4 router tests: `CommandRouterTests` covers native MediaRemote routing,
  reported-name command selection, unsupported-command fallback, plain-adapter
  pass-through and `pauseOthers` selection exclusion.
- Stage 4 bridge E2E: Chromium toggle/next/previous reached the page; see
  `docs/nowplaying-browser-bridge.md`.

## Known limitations

- Two tabs with identical metadata are still resolved fail-closed when the
  resolver is used; Raise/Hide follows the existing selection, so the user can
  explicitly choose one in the menu.
- Bridge `next`/`previous` require the page to register Media Session action
  handlers in the MAIN world. Pages without handlers fall back to a targeted
  MediaRemote command to the browser, which acts on the browser's elected media
  session.
- Bridge favorite is available only when MediaRemote reports a `LikeTrack`
  command for the browser; there is no generic page-level favorite.
- Volume for bridge and native players stays on `BSVolumeControlProtocol`;
  MediaRemote has no per-application volume command.
- The status menu now includes bridge tabs with media metadata. This is the
  intended way to select a paused player.
- A tab that briefly disappears from a bridge `state` loses its cached adapter
  and raised flag.
- Safari release still needs Developer ID and notarization; session-scoped
  **Allow Unsigned Extensions** is only for development.
