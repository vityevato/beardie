# MediaRemoteAdapter vendor patches

- Upstream: https://github.com/ungive/mediaremote-adapter
- Pinned commit: `9e9dcbe` ("Also fix Python script line endings")
- License: BSD 3-Clause, see `LICENSE`.
- Built by the `MediaRemoteAdapter` Xcode framework target in `Beardie.xcodeproj`.
  The framework is embedded in `BeardedSpiceControllers.xpc` and loaded only by
  `/usr/bin/perl`; neither the app nor the XPC service links against it.

## Local patches

### `clients` command

- `src/adapter/get.m`, `src/adapter/get.h`: added `internal_get_all_clients()`
  and `adapter_clients()`. Unlike `get --bundle-id`, it reports every registered
  client, including clients without a title or without a readable player path.
- `include/MediaRemoteAdapter.h`: exported `adapter_clients()` /
  `adapter_clients_env()`.
- `bin/mediaremote-adapter.pl`: accepted `clients` and its read-only options
  (`--now`, `--micros`, `--no-artwork`, `--human-readable`).
- `CMakeLists.txt`: no new source file is needed; `clients` lives in `get.m`.

### `reset` command

- `src/adapter/reset.{h,m}`: added `adapter_reset()`, which takes the
  MediaRemote election override over, clears the overridden application and
  disables the override. A fresh process cannot clear the target with a plain
  `false`; it must enable the override first and give the daemon a moment
  between clearing the target and disabling the override.
- `src/private/MediaRemote.{h,m}`: added the private
  `MRMediaRemoteSetNowPlayingApplicationOverrideEnabled` and
  `MRMediaRemoteSetOverriddenNowPlayingApplication` symbols.
- `include/MediaRemoteAdapter.h`, `bin/mediaremote-adapter.pl`, and
  `CMakeLists.txt`: exposed the command.
- The XPC service runs `reset` once at startup, after a failed transaction and
  when the host app disappears.

### `transaction` command (Stage 4)

- `src/private/MediaRemote.{h,m}`: added the private
  `MRMediaRemoteSetOverriddenNowPlayingApplication` symbol.
- `src/adapter/send.m`: added `adapter_transaction`/`adapter_transaction_env`.
  One process performs the whole transaction: point the election override at
  the target bundle, poll `MRMediaRemoteGetNowPlayingClient` until MediaRemote
  elected that application (timeout, fail-closed), send the command, hold the
  override, clear it, and print a JSON result. Every failure path clears the
  override before exiting non-zero.
- `include/MediaRemoteAdapter.h` and `bin/mediaremote-adapter.pl`: exposed
  `transaction --bundle-id=ID --command=N [--election-timeout=MS]
  [--hold=MS]`.
- `src/adapter/send.m`: added `capabilities`, a JSON self-test reporting
  whether targeted transactions, per-client reads, and supported-command
  enumeration are available. The XPC health payload uses it.
- No new source file is needed; both additions live in `send.m`.

## Deliberately not patched in Stage 1

Targeted `send`/transaction commands are not added in this stage. Stage 1 is
read-only and does not send commands; Stage 4 adds the election/transaction
layer described above. Keeping the Stage 1 patch read-only avoided shipping an
untested override path.

## Upstream compatibility

The existing commands and their payloads are unchanged. The new commands are
additive, and `get --bundle-id` behavior is preserved.
