# Now Playing target resolver and Raise/Hide (Stage 3)

- Date: 2026-11-28.
- Stage: 3 of the `beardie-nowplaying-transition-plan`.
- Scope: match an active MediaRemote Now Playing client to a tab reported by
  the Stage 2 browser bridge, then raise that tab and restore the previous tab
  on the next invocation of the existing **Raise/Hide Active Player Window**
  shortcut.
- The legacy web-strategy bridge, the legacy extensions and all media command
  routing stay unchanged until Stages 4 and 6.

## Why a resolver

MediaRemote and the browser bridge describe the same playback in different
terms:

| Source | Browser identity | Tab identity |
|---|---|---|
| MediaRemote | helper bundle plus parent bundle (`com.google.Chrome.helper` → `com.google.Chrome`, `com.apple.WebKit.GPU` → `com.apple.Safari`) | title, artist, album, elapsed time, duration, playback rate |
| Browser bridge | browser bundle and process id | `tabId`, `windowId`, title, URL, Media Session metadata, playback state, position, duration |

The helper PID cannot be compared with the browser PID, so the resolver has to
match on bundle and media metadata. A wrong tab is worse than no action: when
the match is uncertain the shortcut falls back to the legacy behaviour.

## Data flow

```text
Raise/Hide shortcut
  → AppDelegate.activatePlayingTab
      → NowPlayingBrowserTargets.toggle
          → NowPlayingCoordinator.fetchSnapshot          (XPC, read-only)
          → BrowserBridgeService.activeInstances         (app, Stage 2)
          → BrowserTargetResolver.resolve
              → BrowserBridgeService.activateTab / restoreTab
                  → extension: tabs.update + windows.update
```

`NowPlayingBrowserTargets` is gated by both `UseSystemNowPlaying` and
`UseBrowserBridge`. If either flag is off, the completion immediately reports
"not handled" and `AppDelegate` runs the legacy `BSActiveTab` path.

## Matching rules

1. Only clients with `isPlaying == true` and a non-empty title are considered.
2. The client's `effectiveBundleIdentifier` (parent bundle first) must equal an
   active bridge instance's bundle. Helper suffixes (`.helper`, `.renderer`,
   `.gpu`, `.plugin`) are stripped before comparison.
3. The bridge instance and the candidate tab must have been updated within the
   last 15 seconds.
4. A tab is considered only when it has a media title.
5. If both the client and the tab report an artist and the normalized artists
   differ, the candidate is rejected. Both sides read the same Media Session
   metadata, so an artist mismatch means a different playback.
6. When the client and tab report a duration, a difference over 30 seconds is
   penalized; a difference within 2 seconds is rewarded.
7. When elapsed time and tab position are both known, a difference within 5
   seconds is rewarded.

Text normalization lowercases, folds diacritics and width, replaces
punctuation with spaces and collapses whitespace.

## Scoring

| Signal | Points |
|---|---|
| Title exactly equal | 45 |
| Title contains the other normalized title (at least 4 characters) | 35 |
| Title token overlap ≥ 0.75 | 30 |
| Title token overlap ≥ 0.5 | 22 |
| Artist exactly equal | 20 |
| Album exactly equal | 8 |
| Tab playback state is `playing` | 10 |
| Tab updated ≤ 5 seconds ago | 4 |
| Tab updated ≤ 15 seconds ago | 2 |
| Tab is active | 2 |
| Duration within 2 seconds | 4 |
| Position within 5 seconds | 6 |
| Artist missing in the tab while the client has one | −10 |
| Album differs | −5 |
| Position differs by more than 30 seconds | −4 |
| Duration differs by more than 30 seconds | −10 |

A candidate must score at least **45**. The best candidate must also lead the
second-best candidate by at least **8** points (candidates pointing at the same
tab are deduplicated first). Otherwise the result is `nil`, which is the
fail-closed case.

Typical outcomes:

- exact title, artist and playing state: ~80 points, confident;
- exact title with a playing tab and no artist data: ~60 points, confident;
- two tabs with the same title, artist, position and duration: equal scores,
  margin 0 → `nil`;
- same track in a playing and a paused tab: the playing tab leads by 10, so it
  wins;
- a tab whose artist differs: rejected before scoring.

## Raise/Hide lifecycle

The first shortcut press:

1. fetches a fresh Now Playing snapshot;
2. resolves a target;
3. sends `activateTab` with a generated `requestId`;
4. waits up to 3 seconds for `ack.success`;
5. remembers `BrowserResolvedTarget(instanceId, tabId, windowId)`.

The extension records the tab that was active in the target window before the
activation and focuses the target tab and window.

The next shortcut press sends `restoreTab` for the remembered target. The
extension switches back to the recorded tab and focuses its window. A failed or
timed-out restore is treated as handled and clears the remembered target, so
the shortcut does not unexpectedly fall back to the legacy path.

If the remembered instance disconnected, the target is cleared and the
resolver runs again.

## Bridge request handling

`BrowserBridgeService` now keeps a pending-request table:

- every `activateTab` / `restoreTab` gets a UUID `requestId`;
- an `ack` resolves the matching request only when it arrives on the socket of
  the instance the request was sent to;
- a 3-second timeout, an instance disconnect or a service stop fails the
  request;
- completions are delivered on the main queue;
- the Now Playing snapshot fetch has its own 5-second timeout, so an
  unresponsive XPC service falls back to the legacy path instead of wedging the
  shortcut.

## Verification

- `BeardieTests`: 38 tests pass, including 12 `BrowserTargetResolverTests`
  (exact match, helper bundle, bundle mismatch, conflicting artist, ambiguous
  tabs, playing preference, stale instance/tab, paused client, duplicate
  clients, unrelated title) and `activateTab` / `restoreTab` encoding.
- Debug and Release builds of `Beardie` succeed.
- Chromium E2E (Chromium 138.0.7204.49, custom profile, packaged
  `Beardie-NowPlaying.chrome`, native messaging manifest copied into the
  profile):
  - MediaRemote `clients` reported `org.chromium.Chromium` with
    `Stage 3 Test Track` / `Stage 3 Test Artist`, `playing=true`;
  - the bridge received `hello` and a `state` snapshot with one media tab
    every second;
  - Raise resolved the tab with score 97–99; `chrome.tabs.query` in the
    extension reported the media tab as active and the blank tab as inactive;
  - the second invocation sent `restoreTab`, and the blank tab became active
    again;
  - two tabs with identical metadata produced
    `BrowserTargetResolver: ambiguous target ... score=99 next=97`, no tab was
    raised, and the legacy fallback ran.

## Known limitations

- Two tabs with identical media metadata and playback state are ambiguous by
  design; the shortcut falls back instead of guessing.
- Only playing clients are considered. A paused browser tab cannot be raised
  through this path.
- The feature depends on the new extension; the legacy extension path is the
  fallback until Stage 6.
- "Hide" means returning to the previously active tab and focusing its window;
  the bridge does not minimize or hide the browser window.
- Media command routing (play/pause/next/previous/volume) is still the legacy
  path; Stage 4 moves it to the XPC transaction model.
