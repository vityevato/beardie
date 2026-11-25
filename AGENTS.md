# Beardie — agent notes

## Language

- Swift is the preferred language for all new code. Write new types, helpers, UI, services, and tests in Swift whenever the platform and existing architecture allow it.
- Use Objective-C only when it is genuinely required:
  - integrating with an existing Objective-C API or an XPC boundary;
  - a dependency or API is Objective-C-only;
  - making a minimal fix in an existing Objective-C file.
- Do not rewrite existing Objective-C code into Swift just for style. Keep changes scoped to the task.
- Swift code exposed to Objective-C must use `@objc` / bridging headers and preserve existing behavior.

## Project notes

- Main project: `Beardie.xcodeproj`; the workspace is used while CocoaPods remains.
- Minimum macOS version: 13.0.
- Dependencies are moving to Swift Package Manager. Pin versions and commit `Package.resolved`.
- Do not update dependencies unless the task explicitly asks for it.
- Do not commit or push without explicit user approval.
