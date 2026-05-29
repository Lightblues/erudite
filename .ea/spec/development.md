# Development Guide

## Project Structure

```
erudite/                            ← Git repo root (open in VSCode/Claude Code)
├── .ea/
│   ├── spec/                       ← Product & technical specs
│   └── issues/                     ← Task tracking (todo/done)
├── .gitignore
└── Erudite/                        ← Xcode project (open .xcodeproj in Xcode)
    ├── Erudite.xcodeproj/          ← Project file (SPM deps, build settings, signing)
    └── Erudite/                    ← Source code (auto-synced by Xcode)
        ├── App/                    ← @main entry, AppState
        ├── Models/                 ← Data models (Word, ReviewCard, etc.)
        ├── Engine/                 ← Pure logic (FSRS, Scheduler, Statistics)
        │   └── FSRS/
        ├── Services/               ← IO layer (Database, AI, Import/Export)
        │   └── AIProviders/
        ├── ViewModels/             ← @Observable view models
        ├── Views/                  ← SwiftUI views (thin shells)
        │   ├── Main/
        │   ├── Study/
        │   ├── Review/
        │   ├── Library/
        │   ├── Dashboard/
        │   └── AI/
        ├── Resources/
        │   └── Data/words.json     ← Bundled word database
        └── Assets.xcassets/        ← App icon, colors
```

## Tooling

| Tool | Opens | Purpose |
|------|-------|---------|
| **Xcode** | `Erudite/Erudite.xcodeproj` | Build, run, debug, sign, manage SPM deps |
| **VSCode / Claude Code** | `erudite/` (repo root) | Edit specs/issues, git, AI-assisted coding |

## Build & Run

```bash
# Open in Xcode (daily development)
open /Users/frankshi/Projects/app/erudite/Erudite/Erudite.xcodeproj

# Command-line build (CI / quick verification)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project Erudite/Erudite.xcodeproj -scheme Erudite -destination "platform=macOS"
```

- **Run**: Xcode ▶️ (⌘R)
- **Test**: Xcode ⌘U (once test target is added)
- **Never use** `swift build` / `swift run` — those bypass the Xcode project

## Xcode Project Settings

| Setting | Value | Notes |
|---------|-------|-------|
| Deployment Target | macOS 26.5 | Current system |
| Bundle ID | `site.easonsi.Erudite` | |
| Swift Version | 5.0 (with Swift 6 features) | |
| Actor Isolation | `MainActor` default | All types implicitly `@MainActor` |
| App Sandbox | YES | Need entitlements for network (AI API) |
| File Sync | `PBXFileSystemSynchronizedRootGroup` | Files auto-discovered, no manual Xcode add needed |

## Swift 6 Concurrency Rules

This project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`:

- **All types** are implicitly `@MainActor` unless opted out
- **Views / ViewModels** — leave as-is (MainActor is correct)
- **Services doing IO** — mark as `nonisolated(unsafe)` + `Sendable` if needed
- **Pure logic engines** — can stay `@MainActor` if only called from UI thread

## Coding Conventions

### Architecture: MVVM + Repository

```
View (SwiftUI)  ←→  ViewModel (@Observable)  ←→  Service/Repository
     │                                               │
     └── thin shell, no logic          ┌─────────────┼─────────────┐
                                       Database    AI Provider    FSRS Engine
```

### Naming

| Item | Convention | Example |
|------|-----------|---------|
| Swift files | PascalCase | `WordLoader.swift` |
| Types | PascalCase | `struct ReviewCard` |
| Functions / properties | camelCase | `func fetchDueCards()` |
| Directories | PascalCase (match Xcode groups) | `Views/Study/` |
| Spec/issue files | kebab-case or lowercase | `architecture.md`, `erudite-1.md` |

### File Organization

- One primary type per file (matching filename)
- `// MARK: -` sections for logical grouping within a file
- Related extensions can live in the same file
- Keep files under ~200 lines; split if larger

### Dependencies

- **Minimize external deps** — prefer Apple-native frameworks
- Current: GRDB.swift (SQLite)
- Future: possibly swift-markdown (AI response rendering)
- Add via Xcode: File → Add Package Dependencies

### Resources

- `Bundle.main` for loading bundled resources (NOT `Bundle.module`)
- JSON files in `Resources/Data/`
- Word database (`words.json`) is gitignored — generated via build pipeline

## Git Workflow

- Branch from `main` for features
- One issue = one branch = one PR (when applicable)
- Commit messages: imperative, concise ("Add FSRS scheduling logic")
- `.xcodeproj` changes are committed (they track deps, build settings)
- `xcuserdata/` and `DerivedData/` are gitignored

---

## SwiftUI + @Observable Performance Pitfalls

**Critical lessons learned.** These patterns cause infinite render loops (100% CPU, memory explosion):

### 1. NEVER use computed array properties in ForEach

```swift
// ❌ BAD — creates new array every frame → SwiftUI thinks data changed → re-render → ∞
var visibleMessages: [ChatMessage] {
    runtime.messages.filter { !$0.isToolResult }  // NEW array each access
}
// In view:
ForEach(viewModel.visibleMessages) { ... }  // infinite re-render loop

// ✅ GOOD — use the stored array directly, filter inside ForEach
ForEach(runtime.messages, id: \.id) { message in
    if !message.isToolResult {
        ChatMessageView(message: message)
    }
}
```

**Why:** `@Observable` tracks property access. A computed property returning a new `[Struct]` each time is always "different" from last frame (different reference). SwiftUI detects the change → re-renders → re-evaluates → sees "new" array again → infinite loop.

**Rule:** `ForEach` must bind to a **stored** `@Observable` property (array identity stable across accesses), not a computed property that allocates.

### 2. Guard onChange triggers

```swift
// ❌ BAD — fires even when idle, can cascade
.onChange(of: viewModel.someComputedProperty) { ... }

// ✅ GOOD — only react when actually relevant
.onChange(of: viewModel.streamingText) { _, newText in
    if viewModel.isStreaming && !newText.isEmpty {
        proxy.scrollTo("streaming", anchor: .bottom)
    }
}
```

### 3. Avoid expensive per-frame operations in view body

```swift
// ❌ BAD — AttributedString(markdown:) re-parses on every re-render
var body: some View {
    Text(AttributedString(markdown: streamingText))  // expensive during streaming
}

// ✅ GOOD — use plain Text during streaming, markdown only for final messages
if isStreaming {
    Text(streamingText)  // cheap
} else {
    Text(AttributedString(markdown: finalText))  // one-time parse
}
```

### 4. @Observable + struct arrays: identity matters

`@Observable` tracks stored property mutations by reference identity for classes, but for struct arrays (`[ChatMessage]`), SwiftUI relies on `Identifiable.id` for diffing. The array itself is compared by **element identity** not pointer equality.

The subtle trap: if your computed property creates a new array but elements have the same `id`, SwiftUI should theoretically be fine — but in practice, the observation system marks the attribute as "dirty" on every access of a computed property that touches an `@Observable` stored property, causing the render loop.

### 5. Debugging SwiftUI render loops

```bash
# Sample the process to find CPU hotspot
sample <PID> 5 -f /tmp/sample.txt

# Key indicators in the sample:
# - Main thread 99%+ in `NSRunLoop.flushObservers()` → render loop
# - `GraphHost.runTransaction` / `AG::Subgraph::update` → attribute graph updating
# - `ForEachState.applyNodes` → ForEach is the hot spot
# - `NSTextFieldCell _invalidateEffectiveFont` → Text view re-measuring

# Check memory growth (indicates unbounded re-render)
grep "Physical footprint" /tmp/sample.txt
```

### Summary: Safe Patterns for This Project

| Context | Pattern |
|---------|---------|
| ForEach data source | Always a stored `@Observable` property, never a computed array |
| Filtering in lists | Filter inside ForEach body (`if !msg.isToolResult { ... }`) |
| onChange | Always guard with a boolean check to prevent cascading |
| Streaming text | Plain `Text()` during stream, `AttributedString` only on final |
| Animation | Use declarative `.animation(.repeating)`, never `Task.sleep` loops for visual effects |
| scrollTo | Only trigger when actually streaming/new message, not on every render |
