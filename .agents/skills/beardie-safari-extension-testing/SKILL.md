---
name: beardie-safari-extension-testing
description: Use when testing the Beardie Now Playing Safari Web Extension end-to-end, including asking the user to enable Allow Unsigned Extensions or the extension in Safari.
---

# Beardie Safari Web Extension E2E

## Why Safari needs its own procedure

`NowPlayingSafari.appex` is a Safari app extension, not a Chrome-style
extension. Safari only loads it for the current session when **Develop → Allow
Unsigned Extensions** is enabled. Apple Development and ad-hoc signatures are
both treated as unsigned; only a Developer ID build with notarization loads
without this flag.

The flag resets when Safari quits. **Do not assume the user enabled it once for
an earlier test.**

## Asking the user

The user is available to perform the Safari UI steps. Ask explicitly and wait
for confirmation before continuing. Use a chat card with a “done, continue”
button so the test actually waits instead of guessing.

The two actions are:

1. Safari → Develop → **Allow Unsigned Extensions**.
2. Safari → Settings → **Extensions** → **Beardie Now Playing**: enable it and
   choose **Allow on All Websites**.
3. Reload the test page and keep Safari open.

If the user reports that the extension icon appears and disappears immediately,
or Safari lists duplicate Beardie entries, stop: Safari has cached stale
extension state. Reboot and retry the clean setup; do not “fix” it by rebuilding
or re-signing in the same session.

## Clean setup (one per Safari session)

1. Build a single Debug app. Do not install it into `~/Applications`; running
   from the build products directory is enough.
2. Register exactly one appex:

   ```sh
   pluginkit -a "$PWD/DerivedData/Build/Products/Debug/Beardie.app/Contents/PlugIns/NowPlayingSafari.appex"
   pluginkit -m -A -D -v -i com.calm-apps.mac.beardie.nowplaying.safari
   ```

3. Launch that app with:

   ```sh
   open -n "$PWD/DerivedData/Build/Products/Debug/Beardie.app" \
     --args -UseSystemNowPlaying YES -UseBrowserBridge YES \
     -DebugLogLevel YES -BeardieDebugCommands YES
   ```

   `-UseBrowserBridge YES` is required for the bridge. `-UseSystemNowPlaying`
   is needed only for native targeted commands.
4. Launch Safari on the local test page and ask for the two user actions above.

Do not rebuild, re-sign, copy or change the `CFBundleIdentifier` of the appex
during one Safari session. Safari caches extension identity and state; a new
signature or bundle id usually leaves a stale enabled entry, the appex process
does not start, and the extension icon can appear and disappear.

## Expected successful flow

- The native `bridge` message returns a non-zero `port` and `token`.
- The app log contains `BrowserBridgeService: hello com.apple.Safari` and a
  `state` line for the Safari tab.
- The content script reports the test page.

The Safari manifest installs the MAIN-world Media Session shim dynamically from
the background page (`browser.scripting`, `persistent: true` on macOS).
`next`/`previous` reach the page's handlers through that shim; `play`/`pause`/
`toggle` use the content script. If dynamic registration is unavailable,
next/previous fall back to a targeted MediaRemote command to the browser.

Bridge command routing depends on Beardie having **Accessibility** permission:
the app's player selection includes bridge tabs only when accessibility is
enabled. After rebuilding the Debug app, macOS may reset that permission; grant
it again before testing commands.

## Diagnostics

Safari WebExtension storage exposes the background page state at:

```text
~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebExtensions/Default/<bundle-id>/LocalStorage.db
```

Useful keys:

- `BeardieNowPlayingBridgeResponse` — native handler response: `port`, `token`,
  `protocolVersion`;
- `BeardieNowPlayingLastError` — discovery/WebSocket error;
- `BeardieNowPlayingStatus` — `connected`, `closed`, `error`.

A valid `port` with `Status=closed` usually means the bridge connected to a
stale app instance from an earlier build. Start the app from the same build and
reload the Safari page.

## App group caveat

The appex is sandboxed and normally reads the bridge endpoint from the shared
app group. In ad-hoc/unsigned local builds the app group may not be honored, so
the native `bridge` response can contain `port = 0` even though the app is
running.

- Prefer a signed Debug build with team `TC3Q7MAJXF` for Safari tests.
- Make sure the running app and the appex are from the same build/path and the
  app is still running.
- Do not add test-only endpoint fallbacks to production code without an
  explicit decision.
