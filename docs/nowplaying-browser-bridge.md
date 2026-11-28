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
- handles `hello`, `state` and `ack`;
- exposes `activeInstances` and the Stage 3 `activateTab` / `restoreTab`
  request/ack API;
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

The adapter implements `toggleTab` as `activateTab` on the first call and
`restoreTab` on the next. Playing or paused state is not a condition for
Raise/Hide; it only contributes to selection through `isPlaying`. The full
flow, paused behaviour and selection/matching split are described in
`docs/nowplaying-target-resolver.md`.

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
- `{"type":"ack","requestId":"...","success":true}`.

Server to client:

- `helloAck`;
- `getState` with a request id;
- `activateTab` / `restoreTab` with tab/window ids (used by the Stage 3
  Raise/Hide flow; see `docs/nowplaying-target-resolver.md`);
- `command` for play/pause/seek in the content script.

Timestamps in tab state are JavaScript epoch milliseconds; the Swift decoder
uses `.millisecondsSince1970`.

## Chrome MV3 extension

Source: `BrowserExtensions/nowplaying/`.

- `chrome/manifest.json`: MV3, service worker, `nativeMessaging`, `tabs`,
  `storage`, `alarms`, `<all_urls>` host access.
- `chrome/background.js` imports the shared core.
- `shared/content.js` publishes Media Session and media-element state from all
  frames; `shared/background.js` handles discovery, WebSocket, tab snapshots
  and commands.
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

- `BrowserExtensions/nowplaying/safari/manifest.json` uses an event page:
  `background.scripts` + `persistent: false` (the Stage 0 spike showed that the
  service-worker WebSocket does not connect in Safari).
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
  - `state` messages reported one media tab every second.
- Native messaging connector smoke:
  - `{"msg":"bridge"}` returns `port`, `token`, `protocolVersion`, `browser`,
    `bundleId`, `pid`.
- Safari E2E (ad-hoc build, session-scoped **Allow Unsigned Extensions**):
  - native messaging `bridge` returned `port`, `token`, `protocolVersion`;
  - WebSocket hello arrived with `com.apple.Safari`;
  - `state` messages reported one media tab with `Safari Test Track` by
    `Safari Test Artist` every second.
  - Diagnostic keys in `browser.storage.local`:
    `BeardieNowPlayingStatus=connected`, `BeardieNowPlayingBridgePort`,
    `BeardieNowPlayingLastError=""`.
- Safari appex: built, signed, embedded and registered (`pluginkit`).

## Known limitations

- Stage 2 collected state only. Stage 3 exposes bridge tabs as
  `BrowserBridgeTabAdapter` players and adds Raise/Hide, including paused tabs;
  see `docs/nowplaying-target-resolver.md`.
- Content-script commands are limited to play/pause/toggle/seek on the media
  element; site-specific next/previous is Stage 4 work.
- Artwork URLs are published, but artwork bytes are not downloaded yet.
- `BrowserTargetResolver` remains a matcher for Stage 4 command routing and does
  not select the current player. Same-track ambiguity fails closed when the
  resolver is used; Raise/Hide follows the existing menu/frontmost selection.
- The legacy web-strategy bridge and extensions are intentionally unchanged.
