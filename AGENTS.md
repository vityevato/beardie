# Beardie — agent notes

## Language

- Swift is the default language for all new code and for any code we need to change. Write new types, helpers, UI, services, and tests in Swift whenever the platform and existing architecture allow it.
- If a task requires modifying an existing Objective-C implementation, migrate that implementation to Swift as part of the task instead of adding another Objective-C patch. Keep the Objective-C-facing API stable with `@objc`, `@objc(...)`, bridging headers, or a thin compatibility wrapper, and update call sites in the same change.
- Objective-C is still allowed where it is genuinely required:
  - integrating with an existing Objective-C-only API or an XPC boundary;
  - a dependency or API is Objective-C-only;
  - a C/Objective-C ABI or runtime constraint makes Swift impractical.
  In those cases keep the Objective-C surface as thin as possible and put new logic in Swift.
- Scope migrations to the file(s) the task actually changes. Do not mechanically rewrite unrelated Objective-C files just for style.
- A migration must preserve behavior and the existing public/Objective-C API. For large or risky files, do a behavior-preserving Swift migration first, then make the functional change as a separate step.
- Swift code exposed to Objective-C must use `@objc` / bridging headers and preserve existing behavior.

## Documentation and comments

- All documentation in the repository must be written in English: Markdown
  files, docs, READMEs, and other project documentation.
- All source-code comments must be written in English, including file headers,
  inline comments, and documentation comments.
- Do not add Russian or other non-English prose to documentation or source
  comments, even when the conversation is in another language.

## Naming

- New Swift files and types do not need the `BS` prefix. Swift types are scoped by the module/target, and the project context is already clear.
- Use a clear, descriptive name; adding `BS` to new Swift code is optional and should not be mechanical.
- Keep existing Objective-C `BS`-prefixed names for compatibility. Do not rename existing types just to remove the prefix.
- When a new Swift type is used from Objective-C or a XIB and the runtime name matters, choose the name explicitly with `@objc(...)`.

## Project notes

- Main project: `Beardie.xcodeproj`; use `-project Beardie.xcodeproj` in `xcodebuild` commands. Dependencies are managed by Swift Package Manager.
- Minimum macOS version: 27.0. Do not add compatibility fallbacks for macOS 13–26.
- Dependencies are managed by Swift Package Manager. Pin versions and commit `Package.resolved`.
- Do not update dependencies unless the task explicitly asks for it.
- Do not commit or push without explicit user approval.

## UI tests

- UI tests live in `BeardieUITests` and run through the `BeardieUITests` scheme.
- Load `.agents/skills/beardie-ui-testing/SKILL.md` before writing or running UI tests.
- Run UI tests selectively with `-only-testing:`; they need an unlocked GUI session.
- UI tests are local only and must not be added to CI.
- For UI changes, capture `before`/`after` screenshots and compare them for layout, clipping and readability; pixel-perfect similarity is not required.
