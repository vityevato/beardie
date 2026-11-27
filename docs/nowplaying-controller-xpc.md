# BeardedSpiceControllers: Swift migration (Stage 0.5)

- Date: 2026-11-28.
- Stage: 0.5 of the `beardie-nowplaying-transition-plan`.
- Goal: migrate the XPC controller's own Objective-C code to Swift without
  changing behavior. MediaRemote, new XPC methods, and functional changes are
  out of scope.
- Worktree: `nowplaying-controller-swift`, branch `nowplaying-stage-0.5`.

## Migrated files

| Before | After |
|---|---|
| `BeardedSpiceControllers/main.m` | `BeardedSpiceControllers/main.swift` |
| `BeardedSpiceControllers/BeardedSpiceControllers.{h,m}` | `BeardedSpiceControllers/BeardedSpiceControllers.swift` |
| `BeardedSpiceControllers/BSCService.{h,m}` | `BeardedSpiceControllers/BSCService.swift` |
| `Controllers/BSHeadphoneStatusListener.{h,m}` | `Controllers/BSHeadphoneStatusListener.swift` |

`BeardedSpiceControllers` keeps its Objective-C class name
(`@objc(BeardedSpiceControllers)`); `BeardedSpiceControllersProtocol` and
`BeardedSpiceHostAppProtocol` are unchanged. The bundle ID, `Info.plist`
(`XPCService`, `ServiceType = Application`), and `Components.entitlements`
are unchanged.

The controller target now has a bridging header,
`BeardedSpiceControllers/BeardedSpiceControllers-Bridging-Header.h`. It only
imports the Objective-C headers needed by Swift: the XPC protocols,
`BSSharedResources`, `SPMediaKeyTap`, `DDHidAppleMikey`, `EHSystemUtils`,
`EHExecuteBlockDelayed`, `NSException+Utils`, and `IOHIDUsageTables`.

`SharedResources.swift` was added to the controller target so Swift logs
(`DDLogDebug`/`DDLogInfo`) honor the same `DebugLogLevel` as the previous
Objective-C logs. Without it, CocoaLumberjackSwift would keep
`dynamicLogLevel = .all`.

## Remaining Objective-C and rationale

| Files | Reason |
|---|---|
| `Controllers/DDHidLib/*` | IOKit/HID wrappers with manual reference counting; out of scope for this stage |
| `Controllers/SPMediaKeyTap/*` | Carbon media key tap; out of scope for this stage |
| `SharedComponents/BeardedSpiceControllersProtocol.h` | XPC/Objective-C boundary and compatibility surface |
| `SharedComponents/BeardedSpiceHostAppProtocol.{h,m}` | XPC/Objective-C boundary and `BS_XPCEvent` |
| `Utils/NSException+Utils.{h,m}` | `tryBlock` is the only way to catch Objective-C exceptions from Swift; it wraps DDHidLib calls |

DDHidLib exceptions (`allMikeys`, `startListening`, `stopListening`) are still
wrapped in `tryBlock`, just as they were previously wrapped in `@try/@catch`.
This preserves the service's resilience to IOKit errors without adding new
Objective-C code.

## Behavior and lifecycle

- `main.swift`: `NSXPCListener.service()`, the delegate,
  `disableAutomaticTermination`, logger initialization, and
  `BSCService.shared` are set up in the same order as before.
- A new exported object is created for every connection and keeps a weak
  reference to its `NSXPCConnection`.
- `BSCService` is a singleton. Media keys, shortcuts, volume, Apple Mikey,
  the headphone listener, rcd control, and command delivery to the app are
  preserved.
- `addConnection`/`removeConnection` still run on the main queue; service
  enable/disable and `rcdControl` run at the same points as before.
- Commands are sent to the app through `remoteObjectProxy` on `workingQueue`
  as before; `volumeUp:`/`volumeDown:`/`volumeMute:` now pass `nil` explicitly
  (previously `performSelector:` was called without an argument for nil
  events).
- The headphone listener observes the default output device and
  `kAudioDevicePropertyDataSource`; `kAudioObjectPropertyElementMaster` was
  replaced with the equivalent `kAudioObjectPropertyElementMain` (macOS 12+),
  with identical behavior.

## Verification

Builds:

- `xcodebuild -scheme BeardieControllers -configuration Debug` — succeeded.
- `xcodebuild -scheme Beardie -configuration Debug` — succeeded.
- `xcodebuild -scheme Beardie -configuration Release` — succeeded.
- Signed Debug build (`Apple Development`, team `TC3Q7MAJXF`) — succeeded.

Unit tests:

- `xcodebuild test -scheme Beardie -only-testing:BeardieTests` — all tests
  passed (14/14).

XPC smoke test:

- The signed Debug app launched and the XPC service started.
- Controller log: `New connection`, `rcdControl enabled`,
  `Shortcut event tap started`, `active: true`, 9 shortcuts.
- App → XPC: `setShortcuts: 9 actions`, `setMediaKeysSupportedApps`, and
  `setPhoneUnplugActionEnabled` were received.
- Manual key run (physical key presses):
  - Media keys Play/Pause, Previous, Next — received by the XPC controller and
    delivered to the app (`Refreshing tabs...`, `isPlaying result` in the app
    log);
  - volume up/down/mute — received by the XPC controller and delivered to the
    app;
  - global shortcut Control+Option+Space — `Shortcut action: 0` in XPC and
    handled in the app;
  - headphone plug/unplug — `headphonePlugAction` and
    `headphoneUnplugAction` in the XPC controller, command delivered to the
    app;
  - shortcut recording in Preferences — `setShortcutsRegistrationEnabled: NO`
    while recording, `setShortcuts` + `YES` on cancel/finish.
- `kill -9` of the XPC process: launchd restarted the service and the app
  re-sent its settings; the log shows a new `New connection` and 9 shortcuts.
- On app quit: `rcdControl disable`, `rcdControl load`,
  `Shortcut event tap enabled: false`, and the connection was removed.

Every Stage 0.5 manual regression item passed on the signed Debug build.

## Next stages

Stage 0.5 does not add MediaRemote, a LaunchAgent, or new XPC methods.
`NowPlayingService`, `ElectionController`, and the MediaRemote adapter arrive
in Stages 1/4 according to the plan.

Known behavior inherited from the original Objective-C code: if XPC is killed
(`kill -9`) and the app is then closed, the new `BSCService` instance does not
know that the previous instance unloaded `com.apple.rcd`, so it does not load
it back. This is not a migration regression; recovery after a kill belongs to
Stage 4.
