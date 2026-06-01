---
id: erudite-32
title: "GUI config: Keychain-backed AppConfig + Settings window + OpenRouter default"
status: done
priority: high
estimate: M
---

## Objective

Make the app shippable via Homebrew without hardcoding API keys.
Today's bundled `Resources/Config.json` is fine for solo dev but
fatal for distribution: every user would inherit my keys, or
unwrap an empty file with no UI to fill it.

Pre-this-issue stack:

- `AppConfig.shared` was a `Codable struct` that read
  `Bundle.main → Config.json` once at launch.
- The four call-sites (`DictionaryAPIService`, `BackgroundAI`,
  `AgentRuntime`, `AnthropicClient` error message) all read
  through `AppConfig.shared`.
- Config errors pointed users at "Config.json" — invisible from
  the app and unreachable in a sandboxed Homebrew install.

Goal: GUI-managed secrets, **single-Mac local storage** (no iCloud
in this issue — see Decisions), zero behavior change at the four
call-sites.

## Decisions

### Storage layer
- **Secrets** (`mwDictionaryKey`, `mwThesaurusKey`, `aiApiKey`) →
  **macOS Keychain** (`kSecClassGenericPassword`).
  - Encrypted at rest. UserDefaults stores plain plist —
    `defaults read` and Time Machine would expose plaintext keys.
  - Survives app reinstall (Keychain is system-owned, not the
    app sandbox container).
  - **No `kSecAttrSynchronizable`** — local only. iCloud Keychain
    sync requires a paid Apple Developer Program account and adds
    cross-device-conflict failure modes that don't earn their
    weight for a single-device study app.
- **Non-secret prefs** (`aiBaseURL`, `aiModel`, `aiFastModel`) →
  **UserDefaults**. Same pattern as the existing `AppSettings`.
  Plaintext is fine; reading is hot-path-cheap.

### Why no iCloud / CloudKit
- Single-device usage (GRE prep is deep work; users don't
  fan-out across machines).
- Bigger needs (DB + history sync) are better served later via
  CloudKit, not via half-measures here.
- Cross-device migration in the meantime: P2/P3 will add
  Settings → Backup export/import (config JSON + DB SQLite +
  weekly auto-backup). 4/5 of the real "I switched Macs"
  scenarios are covered without the sync complexity.

### Default endpoint
- **OpenRouter** (`https://openrouter.ai/api/v1/messages`,
  `openrouter/auto`) replaces the previous Anthropic/Sonnet
  defaults.
  - Multi-model gateway with self-serve free credits, friendlier
    onboarding than getting an Anthropic console invite.
  - Wire-format compatible with `AnthropicClient`'s existing
    Bearer-auth path (the `isOfficialAPI = url.contains("anthropic.com")`
    check still routes correctly).
  - `openrouter/auto` is the "let the gateway choose" alias —
    the safest zero-config default; users can override with a
    specific model if they care.
- **No default API key shipped.** A free-credit-only key would
  be (a) abusable by anyone running brew install, (b) violating
  OpenRouter ToS on key sharing, (c) a debugging nightmare when
  the credits run out and "the app stops working." The Settings
  header instead deep-links to `openrouter.ai/keys` so a user
  is one click away from their own key.

### Settings shape
- **Independent window** (macOS HIG standard — Apple's own apps
  all do this, ⌘, opens it). Rejected sidebar-tab approach
  because the configuration is one-time setup, not a working
  surface.
- **Toolbar gear icon** as discoverable mouse entry — `⌘,` alone
  is invisible to new users.
- **One Section, not two** — Key + Base URL + Model + Fast Model
  share a single Section. Splitting "key" from "optional
  overrides" added vertical space without clarity.
- **Field prompts replace footer hints** — `prompt:` shows the
  default value (`openrouter/auto`, `openrouter.ai/api/v1/messages`,
  `same as Model`) inline as gray text. Frees the footer for the
  one thing that matters: where keys are stored, and that you
  can override the endpoint.

### AI-disabled UX
- Chat panel shows a "key.slash" placeholder with a
  `SettingsLink` button when `!hasAIKey`. Input field disabled +
  half-opaque so the user sees there is an input but understands
  it's gated.
- AI tab not hidden — discoverable basic capabilities, blocked
  on the missing prerequisite. Aligns with the "let users feel
  the app first" philosophy.

## Files

### Added
- `Erudite/Erudite/App/KeychainStore.swift` — thin SecItem
  wrapper. `get(account)`, `set(value, for: account)`,
  `delete(account)`. Service = bundle id; one item per account.
  `set("")` deletes (callers don't need a "clear key" path).
  Update-then-add pattern avoids `errSecDuplicateItem`. Uses
  `kSecAttrAccessibleAfterFirstUnlock` so the keys are readable
  once the user has logged in (background AI tasks may run
  while screen is locked).
- `Erudite/Erudite/Views/Settings/SettingsView.swift` — TabView
  with `AISettingsTab` and `DictionarySettingsTab`. SecureField
  + show/hide toggle + paste-from-clipboard. "Test Connection"
  / "Test Lookup" buttons (one-shot HTTP probes scoped to the
  Settings layer — not shared with production AI/dict services
  because they don't share retry/streaming/parsing).

### Rewritten
- `Erudite/Erudite/App/AppConfig.swift` — was a `Codable struct`
  loaded from bundle JSON, now an `@Observable` class:
  - Stored properties read/write Keychain (secrets) or
    UserDefaults (prefs) via `didSet`.
  - **Same field names** + `static let shared` preserved, so
    every existing call-site (`AppConfig.shared.aiApiKey`, etc.)
    compiles unchanged — minimal blast radius.
  - `defaultBaseURL` / `defaultModel` exposed `static let` so
    `SettingsView` shows them as field prompts without
    re-hardcoding strings.
  - Resolved-getters fall through: `aiFastModel` → `aiModel` →
    `defaultModel` (was: → Haiku, which a non-Anthropic gateway
    might not support).

### Modified
- `Erudite/Erudite/App/EruditeApp.swift` — added
  `Settings { SettingsView() }` Scene. ⌘, automatic.
- `Erudite/Erudite/Views/Main/ContentView.swift` — added a
  `ToolbarItem` with `SettingsLink { Image(systemName: "gearshape") }`
  next to the AI panel toggle.
- `Erudite/Erudite/Views/AI/AIChatPanel.swift` — gates content
  on `AppConfig.shared.hasAIKey`. New `missingKeyState` view
  with `SettingsLink` CTA. Input disabled+dimmed when no key.
- `Erudite/Erudite/Services/AI/AnthropicClient.swift` — error
  string `"Please check your key in Config.json."` →
  `"Open Settings (⌘,) to update your key."`
- `Erudite/Erudite/Services/AI/AgentRuntime.swift` — same
  error-message update at the runtime guard.

### Deleted
- `Erudite/Erudite/Resources/Config.json` — was git-ignored;
  no longer loaded at runtime.

### Retained as documentation
- `Erudite/Erudite/Resources/Config.example.json` — top-of-file
  comment marks it deprecated. Kept as a quick reference for
  what fields exist; not consumed by code.

## Verification

- `xcodebuild` clean across all commits.
- Fresh launch with empty Keychain: AI panel shows "AI Companion
  is disabled" + Open Settings button. Library still works
  (Free Dictionary fallback). MW lookups skipped silently.
- Settings → AI tab → paste OpenRouter key + Test Connection →
  green "Connected" status from a 1-token POST.
- Settings → close → AI panel **immediately** unlocks (no
  restart). `@Observable` propagation verified.
- Toolbar gear icon visible on first launch; click opens
  Settings window.
- Keys persist across app reinstall (verified Keychain entry
  via `security find-generic-password -s site.easonsi.Erudite`).

## Acceptance

- [x] No `Config.json` consumed at runtime (deleted from
  Resources, no Bundle load path remains)
- [x] All four AppConfig call-sites unchanged
- [x] Keys stored encrypted (Keychain), not in UserDefaults
- [x] Settings window via ⌘, AND toolbar gear icon
- [x] Default base URL / model = OpenRouter / `openrouter/auto`
- [x] No bundled API key
- [x] AI panel gracefully disabled with deep-link to Settings
- [x] Build clean, no behavior regression for existing users
      with valid keys
- [x] Specs updated (architecture.md, README.md, data.md,
      lessons.md)
