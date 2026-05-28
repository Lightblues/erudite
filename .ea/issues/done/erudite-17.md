---
id: erudite-17
title: "Dynamic dictionary with MW/FreeDict API cache"
status: done
priority: high
estimate: M
---

## Objective

Replace the "jump to Eudic" fallback with an in-app dictionary lookup system. Unknown words are fetched via API, displayed in popover, and permanently cached to local DB.

## Context

- `Services/DictionaryAPIService.swift` — **Created** — MW Collegiate + Thesaurus + Free Dictionary API client
- `Services/WordLookupService.swift` — **Rewritten** — Sync (local) + async (API) lookup with cache + source upgrade logic
- `Services/DatabaseService.swift` — **Modified** — Added `insertCachedWord()` + `updateCachedWord()`
- `Views/Components/InteractiveText.swift` — **Modified** — Async lookup flow with loading/not-found states
- `Views/Components/WordPopoverView.swift` — **Modified** — "Show all N definitions" expand, MW/Eudic footer links, NotFoundPopoverView
- `App/AppConfig.swift` — **Created** — JSON config loader for API keys
- `Resources/Config.json` — **Created** (git-ignored) — Actual API keys
- `Resources/Config.example.json` — **Created** (committed) — Template
- `Erudite/Erudite.entitlements` — **Created** — `network.client = true` for App Sandbox
- `Erudite.xcodeproj/project.pbxproj` — **Modified** — CODE_SIGN_ENTITLEMENTS reference

## Features Implemented

- [x] MW Collegiate API integration (definitions, examples, etymology)
- [x] MW Thesaurus API integration (synonyms, antonyms)
- [x] Free Dictionary API as fallback (no API key required)
- [x] Priority system: MW > FreeDict > "Not Found"
- [x] Permanent caching to local SQLite (INSERT OR IGNORE)
- [x] Source tracking via tags (`source:mw`, `source:free_dict`)
- [x] Auto-upgrade: FreeDict cache → MW when keys available
- [x] Popover: max 2 definitions by default + "Show all" expand
- [x] Popover footer: "Merriam-Webster" web link + "Eudic" app link
- [x] NotFoundPopoverView for words missing from all sources
- [x] App Sandbox network entitlement (`com.apple.security.network.client`)
- [x] Config.json / Config.example.json pattern (git-safe API key management)

## Acceptance

- [x] Click word in local DB → instant popover
- [x] Click unknown word → API fetch → popover with definitions
- [x] Same word second time → instant (cached)
- [x] Offline: unknown word → "Not Found" + Eudic link
- [x] MW web link opens browser
- [x] `xcodebuild build` succeeds
