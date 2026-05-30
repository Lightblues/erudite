# Erudite

AI-native macOS app for GRE vocabulary learning. Built with Swift + SwiftUI.

## Goal

A personal GRE prep tool with:
- FSRS-powered spaced repetition (state-of-the-art scheduling algorithm)
- Context-aware AI teacher (always-present, adapts to learning patterns)
- Multiple review modes (flashcard, quiz, SE pairing, speed review)
- Word root analysis and semantic clustering

## Project Structure

```
erudite/
├── CLAUDE.md                       ← You are here
├── .ea/
│   ├── spec/                       ← Product & technical specs (see below)
│   └── issues/{todo,done}/         ← Task tracking
├── .gitignore
└── Erudite/                        ← Xcode project
    ├── Erudite.xcodeproj
    └── Erudite/                    ← Source (auto-synced by Xcode)
        ├── App/                    ← @main entry, AppState, AppConfig, Log
        ├── Models/                 ← Word, WordSummary, ReviewCard, StudySession, WordList
        ├── Engine/FSRS/            ← Scheduling algorithm (stub, to be implemented)
        ├── Services/               ← DatabaseService (GRDB), WordLoader, Pronunciation
        ├── Services/AI/            ← AI Companion (AgentRuntime, SSE, tools, memory, tracing)
        ├── ViewModels/             ← ChatViewModel
        ├── Views/                  ← SwiftUI views (Main, Plan, Study, Library, Dashboard, AI, Components, Debug)
        └── Resources/Data/         ← Bundled word database (words.json)
```

## Key Specs

- [.ea/spec/product.md](.ea/spec/product.md) — Product vision, GRE context, roadmap phases
- [.ea/spec/features.md](.ea/spec/features.md) — Detailed feature design & interaction modes
- [.ea/spec/ai-system.md](.ea/spec/ai-system.md) — AI Teacher 3-layer architecture
- [.ea/spec/ai-companion.md](.ea/spec/ai-companion.md) — AI Companion: agent, memory, tools, proactive
- [.ea/spec/data.md](.ea/spec/data.md) — Data models, SQLite schema, word database pipeline
- [.ea/spec/architecture.md](.ea/spec/architecture.md) — Tech stack, FSRS algorithm, dependencies
- [.ea/spec/development.md](.ea/spec/development.md) — Dev workflow, build commands, coding conventions

## Development

- **IDE**: Xcode (open `Erudite/Erudite.xcodeproj`)
- **Build**: Xcode ▶️ (⌘R) or `xcodebuild build -project Erudite/Erudite.xcodeproj -scheme Erudite`
- **Stack**: Swift 5.0 + Swift 6 concurrency, SwiftUI, GRDB.swift, macOS 26.5
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (all types implicitly @MainActor)
- **Resources**: Use `Bundle.main` (not `Bundle.module`)

## Conventions

- Architecture: MVVM + Repository pattern
- ViewModels: `@Observable` (not ObservableObject)
- Views: Thin shells — no business logic
- One primary type per file
- Minimal external dependencies (prefer Apple frameworks)
