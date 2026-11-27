# Now Playing: MediaRemote adapter inside the XPC controller (Stage 1)

- Date: 2026-11-28.
- Stage: 1 of the `beardie-nowplaying-transition-plan`.
- Scope: vendor the MediaRemote adapter, build it as a private framework, and
  expose read-only Now Playing data through the XPC controller. Commands, the
  election controller and UI changes are out of scope.
- Result: read-only Now Playing data flows from MediaRemote to the app through
  the XPC service. The app never links against MediaRemote.

## Architecture

```text
Beardie.app (Swift)
  NowPlayingCoordinator
  NowPlayingXPCClient
      │ NSXPCConnection
BeardedSpiceControllers.xpc (Swift)
  NowPlayingService
  MediaRemoteAdapterRunner
      │ Process: /usr/bin/perl
  Contents/Resources/mediaremote-adapter.pl
  Contents/Frameworks/MediaRemoteAdapter.framework
      │ dlopen inside the Perl process
  /System/Library/PrivateFrameworks/MediaRemote.framework
```

The private framework is loaded only by `/usr/bin/perl`. Neither the app nor
the XPC service has a MediaRemote link dependency. This keeps MediaRemote
access working on macOS 15.4+ where apps can no longer use the framework
directly.

## Vendored adapter

- Upstream: https://github.com/ungive/mediaremote-adapter
- Pinned commit: `9e9dcbe`.
- License: BSD 3-Clause, kept in `Vendor/MediaRemoteAdapter/LICENSE`.
- Patch log: `Vendor/MediaRemoteAdapter/PATCHES.md`.
- Vendored tree: `Vendor/MediaRemoteAdapter` (`src`, `include`, `bin`,
  `LICENSE`, `README.md`, `PATCHES.md`).

Local additions:

- `clients` command: one JSON array with every registered MediaRemote client,
  including clients without a title or a readable player path.
- `reset` command: `MRMediaRemoteSetNowPlayingApplicationOverrideEnabled(true)`
  followed by `false`; this is the only reliable way to clear a stale override
  from a fresh process.
- Targeted `send`/transaction commands are deliberately not added in Stage 1.
  The read-only stage does not send commands; Stage 4 adds election and
  transactions together with the health/watchdog model.

Existing upstream commands and payloads are unchanged.

## Build and embedding

- `MediaRemoteAdapter` is a framework target in `Beardie.xcodeproj`.
- It compiles the vendored sources with Objective-C ARC and
  `-fvisibility=default`; its headers are private to the vendor tree.
- The framework is embedded in `BeardedSpiceControllers.xpc`
  (`Contents/Frameworks`) with code signing on copy. It is not embedded in or
  linked by `Beardie.app`.
- `mediaremote-adapter.pl` is copied to the XPC service resources.
- `MediaRemoteAdapterRunner` resolves both paths from `Bundle.main` at runtime.

## Read-only XPC API

Added to `BeardedSpiceControllersProtocol`:

| Method | Payload |
|---|---|
| `getNowPlayingSnapshotWithCompletion:` | JSON `NowPlayingSnapshot` or nil |
| `getNowPlayingHealthWithCompletion:` | JSON `NowPlayingHealth`, always returned |
| `resetNowPlayingWithCompletion:` | `BOOL` success |

`NowPlayingSnapshot` contains every normalized client:

- stable `sourceIdentifier` (normalized bundle + PID);
- own bundle, parent bundle, PID, display name;
- title/artist/album, playback state, rate, duration, elapsed time;
- supported commands with enabled flags;
- artwork MIME type and a SHA-256 fingerprint. Stage 1 requests
  `--no-artwork`; the parser and artwork cache support image bytes and are
  covered by unit tests, ready for the UI stage.

`get`/`clients` normalization rules:

- `parentApplicationBundleIdentifier` wins over the helper bundle, so Safari
  is matched as `com.apple.Safari` while its MediaRemote client is
  `com.apple.WebKit.GPU`;
- a missing `displayName` falls back to `NSRunningApplication.localizedName`
  and then to the effective bundle;
- a client without a title or metadata is still reported, with `playing=false`
  when no playback state is available;
- `elapsedTimeNow` wins over `elapsedTime` when present.

The XPC service caches snapshots for 1 second and artwork in a small LRU cache
(capacity 8). Missing artwork is not an error.

## Feature flag

`UseSystemNowPlaying` is registered as `NO` in `BeardedSpice/Defaults.plist`.
When enabled, `NowPlayingCoordinator` fetches one snapshot and the health
payload after the XPC connection is created and writes the sources to the log.
There is no UI change.

For local testing, the flag can be passed without changing preferences:

```sh
open -n Beardie.app --args -UseSystemNowPlaying YES
```

## Startup reset

`NowPlayingService.start()` runs `reset` before the first read. The adapter
runner serializes processes, so the reset completes before `clients` starts.
This clears an override left behind by a previous session.

## Deployment target

`MACOSX_DEPLOYMENT_TARGET` is now `27.0` for the project and all targets. The
README requirements were updated to macOS 27. The project no longer provides
compatibility fallbacks for macOS 13–26.

## Verification

- Debug and Release builds of `Beardie` and `BeardieControllers`: succeeded.
- Signed Debug build (`Apple Development`, team `TC3Q7MAJXF`): succeeded; the
  embedded framework is signed with the app.
- `MediaRemoteAdapter` is not linked by the XPC executable
  (`otool -L` confirms no MediaRemote dependency).
- Adapter checks:
  - `test` exits 0 with the upstream test client;
  - `get` returns the selected client or `null`;
  - `clients` returns all clients;
  - `get --bundle-id=PlayerB` returns only that client;
  - `reset` exits 0.
- Two test clients simultaneously: `clients` and the app snapshot both report
  two clients with distinct PIDs and titles.
- Startup reset: the controller log shows `NowPlaying startup reset completed`
  before the first snapshot.
- Healthy XPC: app log reports `adapter=true` and the normalized sources.
- Unhealthy XPC (framework removed from the bundle): health reports
  `adapter=false` with `MediaRemoteAdapter resources are missing`; the app
  reports an invalid payload instead of crashing.
- Unit tests: `NowPlayingTests` covers JSON parsing, Safari parent-bundle
  normalization, metadata-less clients, artwork fingerprint/cache, snapshot
  TTL and invalid JSON; the existing suite still passes.

## Known limitations

- Commands are not routed through the new service yet; the existing media key
  and shortcut paths are unchanged.
- Artwork reads are disabled in the Stage 1 runner (`--no-artwork`); the
  parser and cache are ready and unit-tested, but no UI consumes artwork yet.
  Enabling artwork also needs concurrent pipe reads in the adapter runner.
- The current snapshot method spawns one Perl process per read; the 1-second
  cache keeps debug usage cheap, but a streaming adapter is a possible later
  optimization.
- Election/targeted commands, health gating and the transaction lifecycle are
  Stage 4 work.
