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

- `src/adapter/reset.{h,m}`: added `adapter_reset()`, which enables and then
  disables the MediaRemote election override. A fresh process cannot clear the
  override with a plain `false`, because MediaRemote skips a value equal to the
  last value set by that process.
- `src/private/MediaRemote.{h,m}`: added the private
  `MRMediaRemoteSetNowPlayingApplicationOverrideEnabled` symbol.
- `include/MediaRemoteAdapter.h`, `bin/mediaremote-adapter.pl`, and
  `CMakeLists.txt`: exposed the command.
- The XPC service runs `reset` once at startup before the first read.

## Deliberately not patched in Stage 1

Targeted `send`/transaction commands are not added in this stage. Stage 1 is
read-only and does not send commands; Stage 4 adds the election/transaction
layer together with the external health/watchdog model. Keeping the patch
read-only avoids shipping an untested override path.

## Upstream compatibility

The existing commands and their payloads are unchanged. The new commands are
additive, and `get --bundle-id` behavior is preserved.
