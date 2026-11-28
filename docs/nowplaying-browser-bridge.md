# Now Playing browser bridge (Stage 2)

- Date: 2026-11-28.
- Stage: 2 of the `beardie-nowplaying-transition-plan`.
- Scope: add a separate `BrowserBridgeService` and new Chrome MV3 / Safari Web
  Extension sources. The legacy web-strategy bridge and its extensions remain
  unchanged until Stage 6.
- Result: Chrome MV3 connects through native messaging and a loopback
  WebSocket, and publishes tab/media state. The Safari Web Extension target is
  built, embedded and registered; Safari end-to-end is blocked by Safari's
  signing requirements (see below).

## Architecture

```text
Google Chrome / Chromium (MV3 extension)
  content script: Media Session + DOM media state
  service worker: native messaging discovery + WebSocket client
      │ chrome.runtime.sendNativeMessage("bridge")
beardie-nm-connector
      │ reads app-group defaults: port, token, protocol version
      │ returns browser bundle, PID, endpoint
      │ ws://127.0.0.1:<port>/nowplaying?token=<token>
Beardie.app
  BrowserBridgeService
      │ PSWebSocketServer (loopback only)
      │ hello / state / ack
  app group defaults

Safari Web Extension
  event page: same shared JavaScript core
      │ browser.runtime.sendNativeMessage("com.calm-apps.mac.beardie")
  NowPlayingSafari.appex (SFSafariWebExtensionHandler)
      │ returns port/token/Safari PID
      └─ same WebSocket bridge
```

The legacy `BSStrategyWebSocketServer` is not used by the new bridge. It keeps
serving the existing web strategies until Stage 6; only the native messaging
manifest now also allows the new extension ID.

## App-side service

`BeardedSpice/Services/BrowserBridgeService.swift`:

- listens on `127.0.0.1` only, on a free port;
- generates a random 32-byte token per launch;
- publishes `BrowserBridgePort`, `BrowserBridgeToken` and
  `BrowserBridgeProtocolVersion` in the shared app-group defaults;
- validates the token and `/nowplaying` path before accepting a WebSocket;
- tracks instances by `instanceId`, closes the previous connection when a new
  one arrives, and removes the instance on disconnect;
- handles `hello`, `state`, `ack` and `diagnostic`;
- exposes `activeInstances`, the Stage 3 `activateTab` / `restoreTab`
  request/ack API and the live `isActive` query;
- sends `configure` with the debug flag after `helloAck`; diagnostics are only
  sent when that flag is true;
- exposes active bridge tabs as `BrowserBridgeTabAdapter` players through
  `NowPlayingBrowserTabs`; see the Stage 3 section below;
- clears the published endpoint on stop and on app termination;
- runs only when `UseBrowserBridge` is enabled (default `NO`).

`UseBrowserBridge` is registered in `BeardedSpice/Defaults.plist` as `NO`.
For local testing:

```sh
open -n Beardie.app --args -UseBrowserBridge YES
```

## Stage 3 players

`NowPlayingBrowserTabs` converts every bridge tab with media metadata into a
`BrowserBridgeTabAdapter`, and `AppDelegate.refreshTabs` /
`setActiveTabShortcut` include those adapters next to legacy web tabs, native
apps and Sonos rooms. The existing `autoSelectTabWithForceFocused` /
`BSActiveTab` selection therefore chooses bridge tabs like any other player.

The adapter implements `toggleTab` around a live `isActive` query. Hide runs
only when the browser is frontmost and the player tab is the active tab of the
last focused browser window; otherwise the shortcut raises the player again.
Raise records the current frontmost application (including the browser), then
activates the browser before the extension switches the tab/window, because
Safari can restore its last active tab when it becomes active. The extension
re-captures the previous window and the target window's previous tab on every
Raise, so a Raise that started in the browser replaces stale context. Hide
restores the target tab, focuses the previous Safari window when it differs,
and re-activates the previous application unless it is the browser. Playing or
paused state is not a condition for Raise/Hide; it only contributes to
selection through `isPlaying`. The full flow, paused behaviour and
selection/matching split are described in `docs/nowplaying-target-resolver.md`.

The service also installs the native messaging manifest so the extension can
discover the endpoint even when the legacy `BSWebSocketServerEnabled` option is
off. The legacy uninstall path keeps the manifest while `UseBrowserBridge` is
enabled.

## WebSocket protocol

Client to server:

- `{"type":"hello","protocolVersion":1,"instanceId":"...","browser":"...",
  "bundleId":"...","processIdentifier":123}`
- `{"type":"state","instanceId":"...","tabs":[...]}` with per-tab title, URL,
  media metadata, playback state, position, duration and artwork URLs;
- `{"type":"ack","requestId":"...","success":true}`;
- `{"type":"diagnostic","event":"activate","message":"..."}` — debug only,
  sent after `configure` enables diagnostics.

Server to client:

- `helloAck`;
- `configure` with a `debug` flag; diagnostics are off by default;
- `getState` with a request id;
- `isActive` with tab/window ids; the ack result is true only when this tab is
  the active tab of the last focused browser window;
- `activateTab` / `restoreTab` with tab/window ids (used by the Stage 3
  Raise/Hide flow; see `docs/nowplaying-target-resolver.md`);
- `command` for play/pause/toggle/seek/next/previous in the content script.
  `next`/`previous` go through a MAIN-world Media Session shim
  (`shared/mediasession-main.js`) that wraps the page's
  `navigator.mediaSession.setActionHandler`; the isolated content script and the
  shim exchange DOM CustomEvents. Pages without handlers report failure and the
  app may fall back to a targeted MediaRemote command.

Timestamps in tab state are JavaScript epoch milliseconds; the Swift decoder
uses `.millisecondsSince1970`.

State is event-driven. A content script publishes `mediaState` once when it
loads, then on media and visibility events (`play`, `pause`, `ended`,
`loadedmetadata`, `durationchange`, `seeked`, `ratechange`, `volumechange`);
there is no periodic page polling. The background also publishes on tab and
window changes and on an explicit `getState`. The app sends `getState` when the
status menu opens, so the player list and the selected player are refreshed at
the moment the user acts, not on a timer.

Recovery after the background page or service worker is unloaded uses
`requestState`: on background load and on `getState` the background asks every
content script for its current state, refills the in-memory media cache and
only then publishes `state`. Content scripts stay event-driven and are never
polled on a timer. When a content-script message arrives while the WebSocket is
closed, the background calls `connect()` instead of waiting for the next
reconnect timer.

## Chrome MV3 extension

Source: `BrowserExtensions/nowplaying/`.

- `chrome/manifest.json`: MV3, service worker, `nativeMessaging`, `tabs`,
  `storage`, `alarms`, `<all_urls>` host access.
- `chrome/background.js` imports the shared core.
- `shared/content.js` publishes Media Session and media-element state from all
  frames; `shared/background.js` handles discovery, WebSocket, tab snapshots
  and commands.
- MV3 service workers are non-persistent. The 30-second `alarms` timer is the
  only wake-up and reconnect mechanism; there is no app-side ping or second
  keepalive. When the worker is woken after being stopped, `connect()` plus
  `requestState` restore the socket and the media snapshot.
- The manifest uses a fixed `key` so the extension ID is stable:
  `gbkdkokkajlogmoiecfmbicbhkhalpog`. The matching
  `BS_CHROME_NOWPLAYING_EXTENSION_ID` is in `Config.xcconfig` and is included
  in the native host allowed origins. The private key is not committed; keep
  it with the release secrets.
- `Scripts/prepare-extensions.sh` produces
  `Beardie-NowPlaying.chrome` and its zip next to the legacy extension.

For a custom Chromium `--user-data-dir`, the native host manifest must also be
copied to `<user-data-dir>/NativeMessagingHosts/`. The normal user profile uses
`~/Library/Application Support/Chromium/NativeMessagingHosts/` and
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`.

## Safari Web Extension

Target: `NowPlayingSafari` (`com.apple.Safari.web-extension` appex), embedded
in `Beardie.app/Contents/PlugIns`.

- `BrowserExtensions/nowplaying/safari/manifest.json` uses a persistent
  background page: `background.scripts` + `persistent: true`. macOS-only: iOS
  and iPadOS require non-persistent background pages. The Safari manifest has
  no `alarms` permission; with a persistent background page a second keepalive
  would be redundant.
- `NowPlayingSafariHandler` implements `NSExtensionRequestHandling`, reads the
  shared app-group defaults and returns port/token/protocol version plus the
  running Safari PID (the app-extension process itself is not Safari).
- The app-group constant is generated by `prepare-build` from
  `DEVELOPMENT_TEAM`; the stale `5F2` team override was removed so
  `ConfigConstants.h`, the app and the appex all use
  `TC3Q7MAJXF.com.calm-apps.mac.beardie` in Debug.
- Resources are copied into the appex by a target shell-script phase:
  `manifest.json`, `shared/*.js`, `icons/*.png`.
- Entitlements: sandbox + `$(BS_GROUP)`.

Safari signing caveat: on macOS 27.2.1, Safari rejects Apple Development or
unnotarized Developer ID extensions unless **Allow Unsigned Extensions** is
enabled for the current Safari session. The E2E check was completed with an
ad-hoc build and that session flag; release still requires Developer ID +
notarization. The flag resets when Safari quits, so it must be enabled again
for each dev session.

## Verification

- Debug and signed Debug builds of `Beardie` (including the Safari appex):
  succeeded.
- `BeardieTests`: all tests pass, including 5 `BrowserBridgeTests` for
  hello/state/ack parsing, invalid messages and `getState` encoding.
- Node WebSocket smoke against the service:
  - valid hello/state accepted;
  - invalid token rejected with a close frame;
  - duplicate `instanceId` closes the old connection;
  - state count and media count logged.
- Chrome E2E with Chromium 138:
  - unpacked MV3 extension loaded with the fixed ID;
  - native messaging `bridge` returned port/token/PID;
  - WebSocket hello arrived with `org.chromium.Chromium` and the Chromium PID;
  - `state` messages reported one media tab during the test.
- Native messaging connector smoke:
  - `{"msg":"bridge"}` returns `port`, `token`, `protocolVersion`, `browser`,
    `bundleId`, `pid`.
- Safari E2E (ad-hoc build, session-scoped **Allow Unsigned Extensions**):
  - native messaging `bridge` returned `port`, `token`, `protocolVersion`;
  - WebSocket hello arrived with `com.apple.Safari`;
  - `state` messages reported one media tab with `Safari Test Track` by
    `Safari Test Artist`.
  - Diagnostic keys in `browser.storage.local`:
    `BeardieNowPlayingStatus=connected`, `BeardieNowPlayingBridgePort`,
    `BeardieNowPlayingLastError=""`.
- Safari appex: built, signed, embedded and registered (`pluginkit`).
- Stage 4 bridge command E2E (Chromium 138, packaged extension, local media
  page):
  - the bridge reported one media tab with `Bridge Test Track`;
  - `CommandRouter: bridge next` invoked the page's `nexttrack` handler through
    the MAIN-world shim;
  - `previous` invoked `previoustrack`;
  - `toggle` paused and resumed the media element.
- Stage 4.1 Chrome background recovery (Chromium 138, clean profile):
  - the MV3 service worker was stopped through the DevTools
    `ServiceWorker.stopWorker` command while the media tab was playing and the
    bridge was connected (content scripts stay alive, as in a normal idle
    stop);
  - the app logged `instance ... disconnected`;
  - the 30-second alarm restarted the worker; the bridge reconnected
    (`hello org.chromium.Chromium`) and the `state` sent immediately after
    hello already reported the media tab again (`requestState` recovery);
  - no app-side ping or second keepalive is installed.
- Stage 4.1 Safari background lifecycle (macOS 27.2.1, signed Debug build,
  session-scoped **Allow Unsigned Extensions**):
  - `hello com.apple.Safari` and `state` with `Bridge Test Track` were
    reported after enabling the extension;
  - the Safari tab played for more than 60 seconds without Web Inspector and
    the bridge stayed connected (no `instance ... disconnected`);
  - restarting the app changed the bridge port; the persistent background
    reconnected on its own within five seconds and published `state` again;
  - after selecting the Safari tab in the Beardie menu, `next` and `previous`
    produced `CommandRouter: bridge next/previous` and the page logged
    `nexttrack` / `previoustrack` through the dynamically registered
    MAIN-world shim.
- Chrome uses `alarms` only; the Safari manifest has no `alarms` permission and
  creates no alarms. There is exactly one wake-up mechanism per browser.
- Stage 4 command routing on YouTube/Safari:
  - MediaRemote reports `SkipForward` (17) and `SkipBackward` (18);
  - the name-first resolver prefers `NextTrack`/`PreviousTrack`, then
    `SkipForward`/`SkipBackward`, then numeric fallbacks;
  - next/previous hotkeys seek the video by 15 seconds.
- Raise/Hide lifecycle (Safari, two windows and a different frontmost app):
  - `isActive` is queried live; Hide runs only when the player tab is the
    active tab of the last focused browser window;
  - Raise activates the browser before switching tabs; every Raise re-captures
    the previous window and the target window's previous tab;
  - Hide restores the target tab, focuses the previous Safari window when it
    differs, and re-activates the previous app unless it is the browser itself.
- `BeardieTests`: 61 tests pass, including command-router skip fallbacks,
  `isActive`/`configure` encoding and diagnostic parsing.

## Known limitations

- Stage 4.2 (player switching with `playerNext`/`playerPrevious`) is not
  implemented yet; see `docs/nowplaying-target-resolver.md` and the transition
  plan. Switching players to/from a bridge tab does not use the Raise/Hide
  lifecycle yet.
- Stage 2 collected state only. Stage 3 exposes bridge tabs as
  `BrowserBridgeTabAdapter` players and adds Raise/Hide, including paused tabs;
  see `docs/nowplaying-target-resolver.md`.
- Content-script commands: play/pause/toggle/seek operate on the primary media
  element; next/previous invoke the page's Media Session handlers through the
  MAIN-world shim. Site-specific actions that are not exposed as Media Session
  handlers are not reachable generically.
- Safari supports `world: "MAIN"` only for dynamically registered content
  scripts, not for the MV2 manifest used here. The background registers
  `shared/mediasession-main.js` through `browser.scripting`; Safari E2E
  verified `nexttrack` / `previoustrack` through that registration. If
  registration is unavailable, next/previous fall back to a targeted
  MediaRemote command to the browser.
- Artwork URLs are published, but artwork bytes are not downloaded yet.
- `BrowserTargetResolver` remains a matcher for Stage 4 command routing and does
  not select the current player. Same-track ambiguity fails closed when the
  resolver is used; command routing follows the existing menu/frontmost
  selection.
- The legacy web-strategy bridge and extensions are intentionally unchanged.
