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
- `reset` command: takes the override over, clears the overridden application,
  waits for the daemon and disables the override. A plain `enabled(false)` from
  a fresh process does not clear a target left behind by a dead helper.
- `transaction` command (Stage 4): points the election override at one bundle,
  waits for the election, sends one command, holds the override and clears it.
  See `docs/nowplaying-election-watchdog.md`.
- `capabilities` command (Stage 4): JSON self-test used by the XPC health gate.
- Targeted `MRMediaRemoteSetOverriddenNowPlayingApplication` is loaded only by
  the Perl process, like the rest of MediaRemote.

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

## XPC API

Added to `BeardedSpiceControllersProtocol`:

| Method | Payload |
|---|---|
| `getNowPlayingSnapshotWithCompletion:` | JSON `NowPlayingSnapshot` or nil |
| `getNowPlayingHealthWithCompletion:` | JSON `NowPlayingHealth`, always returned |
| `resetNowPlayingWithCompletion:` | `BOOL` success; refreshes capabilities first |
| `sendNowPlayingCommand:toBundle:hold:completion:` | JSON `NowPlayingCommandResult` or nil |
| `pauseOtherNowPlayingClientsExceptBundle:completion:` | JSON `NowPlayingPauseOthersResult` |

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

## Targeted commands (Stage 4)

`ElectionController` turns the `transaction` command into the only override
writer in the process. A transaction is one Perl process:

```text
setOverriddenNowPlayingApplication(bundle)
  → poll getNowPlayingClient until the effective bundle matches (timeout, fail closed)
  → sendCommand(command)
  → hold
  → setOverriddenNowPlayingApplication(NULL)
```

The XPC service serializes transactions, gates them on `capabilities`, and runs
a `reset` after a failed or killed helper. `pauseOthers` sends `kMRPause` to
every playing client except the selected one, one transaction per client. The
app-side `CommandRouter` uses this only for native players that have a matching
Now Playing client and report the command as supported. Volume stays on the
existing adapter protocol because MediaRemote has no per-application volume
command.

## Health gate

`NowPlayingHealth` now includes `targetedCommandsAvailable`. It is true only
after `capabilities` reports the targeted symbols, per-client reads and
supported-command enumeration. When it is false, `CommandRouter` falls back to
the legacy adapter path and the UI disables commands that have no legacy
transport.

## Feature flag

`UseSystemNowPlaying` is registered as `NO` in `BeardedSpice/Defaults.plist`.
When enabled, `NowPlayingCoordinator` fetches a snapshot and the health payload
after the XPC connection is created, logs the sources, and serves the router's
targeted command path.

For local testing, the flag can be passed without changing preferences:

```sh
open -n Beardie.app --args -UseSystemNowPlaying YES
```

The browser bridge commands are gated separately by `UseBrowserBridge` and do
not require `UseSystemNowPlaying`.

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
  TTL, command lookup by reported name and invalid JSON; `CommandRouterTests`
  covers the transport matrix and capability gating; the existing suite still
  passes (52 tests).

Stage 4 additions:

- `capabilities` reports `targetedCommands=true` on macOS 27.2.1.
- Transaction E2E with two stand-in Now Playing clients: command to a
  non-elected paused client reaches only that client; the elected application
  is restored afterwards; a missing target fails closed.
- `pauseOthers` paused the one playing client through its own transaction.
- App/XPC/Perl kill recovery is documented and verified in
  `docs/nowplaying-election-watchdog.md`.

## Known limitations

- Artwork reads are disabled in the server runner (`--no-artwork`); the parser
  and cache are ready and unit-tested, but no UI consumes artwork yet. Enabling
  artwork also needs concurrent pipe reads in the adapter runner.
- The current snapshot method spawns one Perl process per read; the 1-second
  cache keeps usage cheap, but a streaming adapter is a possible later
  optimization.
- Targeted commands are limited to commands MediaRemote exposes: play, pause,
  toggle, next, previous and like. Volume and site-specific actions stay on the
  adapter protocols.
- MediaRemote command numbers differ between releases. The router prefers the
  identifier reported by the client (for example `LikeTrack` is 21 on macOS
  27.2.1, not the legacy 0x6A).
