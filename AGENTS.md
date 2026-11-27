# Beardie — agent notes

## Language

- Swift is the preferred language for all new code. Write new types, helpers, UI, services, and tests in Swift whenever the platform and existing architecture allow it.
- Use Objective-C only when it is genuinely required:
  - integrating with an existing Objective-C API or an XPC boundary;
  - a dependency or API is Objective-C-only;
  - making a minimal fix in an existing Objective-C file.
- Do not rewrite existing Objective-C code into Swift just for style. Keep changes scoped to the task.
- Swift code exposed to Objective-C must use `@objc` / bridging headers and preserve existing behavior.

## Naming

- New Swift files and types do not need the `BS` prefix. Swift types are scoped by the module/target, and the project context is already clear.
- Use a clear, descriptive name; adding `BS` to new Swift code is optional and should not be mechanical.
- Keep existing Objective-C `BS`-prefixed names for compatibility. Do not rename existing types just to remove the prefix.
- When a new Swift type is used from Objective-C or a XIB and the runtime name matters, choose the name explicitly with `@objc(...)`.

## Project notes

- Main project: `Beardie.xcodeproj`; use `-project Beardie.xcodeproj` in `xcodebuild` commands. Dependencies are managed by Swift Package Manager.
- Minimum macOS version: 13.0.
- Dependencies are managed by Swift Package Manager. Pin versions and commit `Package.resolved`.
- Do not update dependencies unless the task explicitly asks for it.
- Do not commit or push without explicit user approval.

## UI tests

- UI tests live in `BeardieUITests` and run through the `BeardieUITests` scheme.
- Load `.agents/skills/beardie-ui-testing/SKILL.md` before writing or running UI tests.
- Run UI tests selectively with `-only-testing:`; they need an unlocked GUI session.
- UI tests are local only and must not be added to CI.
- For UI changes, capture `before`/`after` screenshots and compare them for layout, clipping and readability; pixel-perfect similarity is not required.
