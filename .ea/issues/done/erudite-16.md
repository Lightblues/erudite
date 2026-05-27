---
id: erudite-16
title: "Interactive Dictionary & Flashcard UI alignment"
status: done
priority: high
estimate: L
---

## Objective

1. Implement an interactive dictionary system: all English text in the app becomes clickable for word lookup (local DB → popover, fallback → Eudic URL scheme).
2. Align Flashcard (StudyView) UI and shortcuts with Typing mode for a consistent experience.
3. Replace fragile SwiftUI `@FocusState` keyboard handling with a robust `NSViewRepresentable`-based key capture system.

## Context

Users encounter unfamiliar words *within* definitions and example sentences. Without interactive lookup, they must manually switch to an external dictionary. Additionally, the Flashcard and Typing modes had inconsistent shortcuts and features, making it confusing to switch between them.

The biggest technical challenge was macOS focus management: SwiftUI's `@FocusState` + `.onKeyPress` repeatedly broke after popover dismiss, button clicks, and phase transitions. The root cause is that macOS uses a First Responder chain, and popovers/buttons steal firstResponder without restoring it.

## Features Implemented

### Interactive Dictionary
- [x] `InteractiveText` component — tokenizes English text, renders each word clickable
- [x] `WordPopoverView` — compact word card shown on click (definitions, examples, mnemonic, synonyms)
- [x] `SynonymChipsView` — clickable synonym chips with lookup
- [x] `WordLookupService` — DB lookup with in-memory cache
- [x] `DatabaseService.fetchWord(bySpelling:)` — case-insensitive lookup
- [x] Common word filter (~120 words: pronouns, prepositions, articles, etc.) — avoids useless lookups
- [x] Eudic URL scheme fallback (`eudic://dict/{word}`) for words not in local DB
- [x] Multi-layer lookup — popover contents are also interactive (recursive)
- [x] `.popover(item:)` binding to eliminate empty-popover race condition
- [x] Applied to: StudyView (definitions, examples, mnemonics), TypingView (word card), WordDetailView (definitions, examples, mnemonics, synonyms)

### Flashcard UI Alignment
- [x] Header bar: progress (done/left) + card state badge + Accent picker + Loop Audio toggle
- [x] Navigation preview: ← prev word / Word List / next word → (same as Typing)
- [x] Word list popover: shows full review queue with state badges, clickable to jump
- [x] Session complete page: stats summary + all words with rating color-coded
- [x] Idle (pause) state: Esc pauses, shows "Press Space to continue"
- [x] Space = toggle reveal (not auto-advance)
- [x] Easy (4/;) allowed without reveal (quick skip known words)
- [x] Click card to toggle reveal (mouse support)
- [x] Shared accent/loop settings with Typing (same UserDefaults keys)
- [x] Skip no longer re-queues card (fixes duplicate word bug)
- [x] Queue deduplication by wordId on load

### Keyboard Shortcuts (aligned)

| Key | Flashcard | Typing |
|-----|-----------|--------|
| Space | Toggle reveal | Toggle word card |
| ←/→ | Go back / Skip | Go back / Skip |
| Esc | Pause → idle | Pause → idle |
| 1-4 / jkl; | Rate (Again/Hard/Good/Easy) | — |
| r | Replay pronunciation | — |
| q | End session | — |
| ⌘R | — | Replay |
| Tab | — | Cycle hide mode |
| Letters | — | Type input |

### KeyCaptureView (Focus System Rewrite)
- [x] `KeyCaptureView` (NSViewRepresentable) — transparent NSView that owns keyboard input
- [x] `acceptsFirstResponder = true` — always accepts keyboard
- [x] `resignFirstResponder()` override — re-grabs focus after 1 runloop cycle
- [x] `windowDidBecomeKey` observer — re-grabs after popover dismiss
- [x] `hitTest → nil` — mouse events pass through to SwiftUI UI layer
- [x] No system beep: `keyDown` never calls `super` for unhandled keys
- [x] `isActive` flag — only captures when the tab is selected and no popover is open
- [x] Replaces all `@FocusState` + timer hacks in both StudyView and TypingView

## Files

| File | Action |
|------|--------|
| `Views/Components/KeyCaptureView.swift` | **Created** — NSViewRepresentable keyboard interceptor |
| `Views/Components/InteractiveText.swift` | **Created** — tokenized clickable text + TextFlowLayout |
| `Views/Components/WordPopoverView.swift` | **Created** — compact word card + SynonymChipsView |
| `Services/WordLookupService.swift` | **Created** — lookup + cache + Eudic fallback |
| `Services/DatabaseService.swift` | **Modified** — added `fetchWord(bySpelling:)` |
| `App/AppState.swift` | **Modified** — added `wordLookupService` |
| `App/EruditeApp.swift` | **Modified** — `windowResizability(.contentSize)` + minSize |
| `Views/Study/StudyView.swift` | **Rewritten** — KeyCaptureView, header, word list, nav preview, idle state, session summary |
| `Views/Study/StudyViewModel.swift` | **Rewritten** — idle phase, accent/loop settings, loop timer, review results tracking, dedup |
| `Views/Study/TypingView.swift` | **Modified** — KeyCaptureView, shared WordPopoverView for word card |
| `Views/Library/WordDetailView.swift` | **Modified** — InteractiveText for definitions/examples/mnemonics/synonyms |

## Acceptance

- [x] Click any underlined English word → popover with definition (or Eudic if not in DB)
- [x] Common words (the, in, is, etc.) are NOT clickable
- [x] Flashcard: Space toggles, Esc pauses, 4/; rates Easy without reveal
- [x] Keyboard works reliably after popover dismiss, button clicks, phase transitions
- [x] No system beep sounds on any key press
- [x] No duplicate words in review queue
- [x] Window does not resize when card content changes
- [x] `xcodebuild build` succeeds
