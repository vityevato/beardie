# BeardedSpiceControllers: Swift migration (Stage 0.5)

- Дата: 2026-11-28.
- Этап: 0.5 плана `beardie-nowplaying-transition-plan`.
- Цель: behavior-preserving перевод собственного ObjC-кода XPC-контроллера на
  Swift. MediaRemote, новые XPC-методы и функциональные изменения не входят.
- Worktree: `nowplaying-controller-swift`, ветка `nowplaying-stage-0.5`.

## Что переведено

| Было | Стало |
|---|---|
| `BeardedSpiceControllers/main.m` | `BeardedSpiceControllers/main.swift` |
| `BeardedSpiceControllers/BeardedSpiceControllers.{h,m}` | `BeardedSpiceControllers/BeardedSpiceControllers.swift` |
| `BeardedSpiceControllers/BSCService.{h,m}` | `BeardedSpiceControllers/BSCService.swift` |
| `Controllers/BSHeadphoneStatusListener.{h,m}` | `Controllers/BSHeadphoneStatusListener.swift` |

`BeardedSpiceControllers` сохраняет ObjC-имя класса (`@objc(BeardedSpiceControllers)`),
`BeardedSpiceControllersProtocol` и `BeardedSpiceHostAppProtocol` не менялись.
Bundle ID, `Info.plist` (`XPCService`, `ServiceType = Application`) и
`Components.entitlements` не менялись.

Добавлен bridging header
`BeardedSpiceControllers/BeardedSpiceControllers-Bridging-Header.h`. В него
вынесены только ObjC-заголовки, нужные Swift-коду: XPC-протоколы,
`BSSharedResources`, `SPMediaKeyTap`, `DDHidAppleMikey`, `EHSystemUtils`,
`EHExecuteBlockDelayed`, `NSException+Utils` и `IOHIDUsageTables`.

`SharedResources.swift` добавлен в target контроллера, чтобы Swift-логи
(`DDLogDebug`/`DDLogInfo`) подчинялись тому же `DebugLogLevel`, что и прежние
ObjC-логи. Без этого CocoaLumberjackSwift использовал бы `dynamicLogLevel = .all`.

## Что осталось на ObjC и почему

| Файлы | Причина |
|---|---|
| `Controllers/DDHidLib/*` | IOKit/HID-обёртки, MRC-код; не входят в объём миграции |
| `Controllers/SPMediaKeyTap/*` | Carbon media key tap; не входит в объём миграции |
| `SharedComponents/BeardedSpiceControllersProtocol.h` | XPC/ObjC-граница, compatibility surface |
| `SharedComponents/BeardedSpiceHostAppProtocol.{h,m}` | XPC/ObjC-граница и `BS_XPCEvent` |
| `Utils/NSException+Utils.{h,m}` | `tryBlock` — единственный способ поймать ObjC-исключения из Swift; используется для вызовов DDHidLib |

Исключения DDHidLib (`allMikeys`, `startListening`, `stopListening`) остались
обёрнутыми в `tryBlock`, как раньше были обёрнуты в `@try/@catch`. Это сохраняет
устойчивость сервиса при ошибках IOKit без добавления нового ObjC-кода.

## Поведение и lifecycle

- `main.swift`: `NSXPCListener.service()`, delegate, `disableAutomaticTermination`,
  инициализация логгера и `BSCService.shared` — в том же порядке, что и раньше.
- Экспортируемый объект создаётся на каждое соединение и хранит weak-ссылку на
  `NSXPCConnection`.
- `BSCService` — синглтон. Media keys, shortcuts, volume, Apple Mikey,
  headphone listener, rcd control и отправка команд в app сохранены.
- `addConnection`/`removeConnection` по-прежнему работают через main queue;
  включение/выключение сервиса и `rcdControl` выполняются в те же моменты.
- Команды app отправляются через `remoteObjectProxy` в `workingQueue`, как и
  раньше; `volumeUp:`/`volumeDown:`/`volumeMute:` теперь передают `nil` явно
  (раньше `performSelector:` вызывался без аргумента для nil-событий).
- Headphone listener слушает default output device и `kAudioDevicePropertyDataSource`;
  `kAudioObjectPropertyElementMaster` заменён на эквивалентный
  `kAudioObjectPropertyElementMain` (macOS 12+), поведение то же.

## Проверки

Сборка:

- `xcodebuild -scheme BeardieControllers -configuration Debug` — успешно.
- `xcodebuild -scheme Beardie -configuration Debug` — успешно.
- `xcodebuild -scheme Beardie -configuration Release` — успешно.
- Подписанная Debug-сборка (`Apple Development`, team `TC3Q7MAJXF`) — успешно.

Unit-тесты:

- `xcodebuild test -scheme Beardie -only-testing:BeardieTests` — все тесты
  прошли (14/14).

Smoke-тест XPC:

- Подписанное Debug-приложение запущено, XPC-сервис стартовал.
- В логе контроллера: `New connection`, `rcdControl enabled`,
  `Shortcut event tap started`, `active: true`, 9 shortcuts.
- App → XPC: `setShortcuts: 9 actions`, `setMediaKeysSupportedApps`,
  `setPhoneUnplugActionEnabled` получены.
- При выходе app: `rcdControl disable`, `rcdControl load`,
  `Shortcut event tap enabled: false`, соединение удалено.

Не проверено автоматически в этой сессии (нужен TCC/Accessibility и
оборудование):

- фактическая доставка media key events (play/pause, next/prev);
- срабатывание глобальных shortcut-сочетаний;
- volume up/down/mute;
- headphone unplug (на текущем аудиоустройстве нет доступного data source).

Эти пункты нужно прогнать вручную на подписанной сборке перед мержем.

## Следующие этапы

Stage 0.5 не добавляет MediaRemote, LaunchAgent и новых XPC-методов.
`NowPlayingService`, `ElectionController` и MediaRemote adapter появляются в
Stage 1/4 согласно плану.
