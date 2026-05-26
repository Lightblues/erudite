---
id: erudite-2
title: Migrate from Swift Package to Xcode native project
status: done
priority: high
estimate: S
---

## Objective

Convert the project from a pure Swift Package (`Package.swift` + `Sources/`) to a proper
Xcode native project (`.xcodeproj`), enabling proper macOS app capabilities: bundle identity,
code signing, entitlements, and standard Xcode build/run/debug workflow.

## Context

- The initial skeleton was built as a Swift Package for quick prototyping
- `swift run` couldn't properly launch GUI (needed `NSApplication.setActivationPolicy` hack)
- Future features (AI API calls) require network entitlement → needs proper .xcodeproj
- Xcode 26.5 uses `PBXFileSystemSynchronizedRootGroup` (auto file sync, no manual references)

## Tasks

- [x] Create new Xcode project via Xcode.app (macOS → App → SwiftUI)
- [x] Move source code from `Sources/Erudite/` → `Erudite/Erudite/`
- [x] Remove `import AppKit` + `NSApplication` activation hack (not needed in Xcode app)
- [x] Change `Bundle.module` → `Bundle.main` in WordLoader
- [x] Add GRDB.swift SPM dependency to .xcodeproj (`packageReferences`)
- [x] Add `@MainActor` / `nonisolated` annotations for Swift 6 strict concurrency
- [x] Verify `xcodebuild build` passes with zero errors
- [x] Remove old SPM artifacts: `Package.swift`, `Package.resolved`, `Sources/`, `Tests/`, `.build/`, `.swiftpm/`
- [x] Update `.gitignore` for Xcode project structure
- [x] Document development workflow in `.ea/spec/development.md`

## Acceptance

- [x] `xcodebuild build` succeeds (BUILD SUCCEEDED)
- [x] App launches from Xcode ▶️ with proper window and sidebar navigation
- [x] No `Bundle.module` references remain (all use `Bundle.main`)
- [x] GRDB resolves and compiles (package version 7.10.0)
- [x] Bundle ID = `site.easonsi.Erudite`, App Sandbox enabled

## Notes

- Console warnings about `com.apple.linkd.autoShortcut` are harmless macOS noise (not errors)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is enabled (Xcode 26 default for new projects)
- Test target not yet added — will be a separate issue
