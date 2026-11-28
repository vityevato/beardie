# Now Playing election transactions and recovery (Stage 4)

- Date: 2026-11-28.
- Stage: 4 of the `beardie-nowplaying-transition-plan`.
- Scope: targeted MediaRemote commands, the election override lifecycle in the
  XPC controller, the health gate and recovery after process failures.
- Player selection stays where it was: `autoSelectTabWithForceFocused:` /
  `BSActiveTab` / `TabAdapter`. `CommandRouter` only picks a transport for the
  player that was already selected.

## Why an override is needed

MediaRemote sends every command to the application it elected as Now Playing.
`MRMediaRemoteSendCommandToApp` and a player path built from another client are
quietly redirected to the elected application. The only reliable way to reach a
different application is the daemon's Now Playing election override:

1. `MRMediaRemoteSetOverriddenNowPlayingApplication(bundleID)`;
2. wait until MediaRemote reports that application as the current now playing
   client;
3. send exactly one command with `MRMediaRemoteSendCommand`;
4. keep the override for a short hold;
5. `MRMediaRemoteSetOverriddenNowPlayingApplication(NULL)`.

The override is system-wide: while it is active, the Mac's media keys and
Control Center also act on the target. It also outlives the process that set
it. Stage 4 therefore keeps it for one command only.

## Transaction lifecycle

`ElectionController` in `BeardedSpiceControllers.xpc` owns the transaction:

- one serial queue; one transaction at a time;
- each transaction is one `/usr/bin/perl` process running
  `mediaremote-adapter.pl transaction`;
- the process waits for the election with a timeout and fails closed when the
  target was not elected;
- every failure path clears the override before exiting non-zero;
- after a failed or killed helper the controller queues a `reset` before the
  next transaction;
- `reset` takes the override over, clears the overridden application, waits for
  the daemon to process the clear and then disables the override; a plain
  `enabled(false)` from a fresh process does not clear a target left by a dead
  helper;
- `pauseOthers` is a series of independent transactions, one `kMRPause` per
  playing client, so no single long-lived override covers the whole series.

The app never calls the override setters. It only asks the XPC service to run a
transaction and receives a JSON `NowPlayingCommandResult`.

## Health gate

The vendored adapter has a `capabilities` command. It reports whether the
targeted transaction symbols, per-client reads and supported-command
enumeration exist on this system. `NowPlayingService.start()` and every reset
refresh that payload; `NowPlayingHealth.targetedCommandsAvailable` carries it to
the app.

`CommandRouter` sends a targeted command only when:

- `UseSystemNowPlaying` is enabled;
- the last health payload says targeted commands are available;
- the selected native application has a matching Now Playing client;
- the command is reported as supported and enabled, or the client does not
  report supported commands at all.

Otherwise the router returns `false` and the existing adapter path runs.

## Recovery model

| Event | Expected behavior |
|---|---|
| XPC killed while the app runs | App's interruption handler recreates the `NSXPCConnection`, resends settings, rebinds `NowPlayingCoordinator`, and runs health/reset. The Perl child may finish its hold and clear the override itself. |
| App killed while XPC is alive | XPC invalidation removes the last connection, terminates the transaction process and queues `reset`. |
| Perl child killed | The runner reports a cancellation/failure; `ElectionController` queues a recovery `reset` before the next transaction. |
| App and XPC both dead | The override can stay until the next start. This is the accepted residual risk; the startup `reset` clears it before the first read. |
| Stale override at startup | `NowPlayingService.start()` runs `reset` before the first snapshot. |
| XPC unhealthy | `targetedCommandsAvailable` is false; targeted commands are not sent and the legacy path is used. |

There is deliberately no separate LaunchAgent or watchdog process. Recovery is
the startup reset, the app reconnect, invalidation handling, and the reset after
a failed helper.

## XPC API

| Method | Payload |
|---|---|
| `sendNowPlayingCommand:toBundle:hold:completion:` | JSON `NowPlayingCommandResult` or nil |
| `pauseOtherNowPlayingClientsExceptBundle:completion:` | JSON `NowPlayingPauseOthersResult` |
| `getNowPlayingHealthWithCompletion:` | `NowPlayingHealth`, now with `targetedCommandsAvailable` |
| `resetNowPlayingWithCompletion:` | resets the override and refreshes capabilities before replying |

## Verification

Local E2E used a Debug-only `BeardieDebugCommands` distributed-notification hook
(`-BeardieDebugCommands YES`) to drive the same `playPauseToggle` / `nextTrack` /
`previousTrack` / `favorite` paths as media keys, plus a `logState` command and
a targeted-command helper. The hook is compiled only in `#if DEBUG` and is not
registered unless the flag is passed.

- Vendor transaction with two stand-in Now Playing applications:
  - playing application B, command `Play` to paused A: only A received `play`,
    the override was cleared afterwards;
  - command `Pause` to A while B was elected: only A received `pause`, B stayed
    elected;
  - a missing target failed after the election timeout with a non-zero exit and
    left the elected application untouched;
  - `capabilities` reported `targetedCommands=true`.
- `pauseOthers` through the app: two clients, one playing; XPC reported
  `paused=1 failed=0` and only the playing client received `pause`.
- App killed mid-transaction (8–10 s hold): the XPC controller terminated the
  Perl process and queued a recovery reset. After a playback transition on
  client B, `get` reported B and a global MediaRemote `pause` reached B, not
  the stale target A.
- XPC killed mid-transaction (6 s hold): the Perl child finished the hold and
  cleared the override; the app logged the lost connection, recreated the XPC
  connection, resent settings and completed the startup reset/capabilities
  check.
- Stale override left by a killed helper: the fixed `reset` (take the override
  over, point it at a known client, clear the target, wait for the daemon,
  disable) restored normal election. A playback transition on the playing
  client won the election and global `send` reached that client. The earlier
  `enabled(true) → enabled(false)` sequence and a plain `set(nil)` did not clear
  the dead helper's target.
- Unit tests: 52 tests pass, including the router transport matrix, command
  lookup by reported name, bridge command encoding, and capability payloads.
