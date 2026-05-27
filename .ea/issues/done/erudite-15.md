---
id: erudite-15
title: "Typing Practice mode (qwerty-learner style)"
status: done
priority: high
estimate: L
---

## Objective

Implement a qwerty-learner-inspired typing practice mode as a separate tab, providing muscle-memory-based vocabulary learning through character-by-character spelling.

## Context

Passive flashcard review has limited retention on desktop. Typing engages motor memory and active recall simultaneously. This mode is independent from FSRS scheduling — it's a complementary learning channel.

## Architecture

- Separate `Typing` tab in sidebar (5 tabs: Today / Flashcard / Typing / Library / Stats)
- Independent `TypingViewModel` + `TypingView` (not nested in flashcard flow)
- Chapter-based pagination from `wordListEntry.sortOrder`
- Typing stats recorded to `typingLog` DB table

## Files

| File | Action |
|------|--------|
| `Views/Study/TypingView.swift` | **Created** — full typing UI, settings, chapter summary |
| `Views/Study/TypingViewModel.swift` | **Created** — state machine, settings persistence, sound effects |
| `Views/Main/ContentView.swift` | **Modified** — 5-tab routing |
| `Views/Main/TodayView.swift` | **Modified** — "Type Practice" button |
| `Views/Study/StudyView.swift` | **Modified** — removed typing branch (now separate tab) |
| `App/AppState.swift` | **Modified** — `SidebarTab` enum: today/flashcard/typing/library/dashboard |
| `Services/DatabaseService.swift` | **Modified** — `typingLog` table + `insertTypingLog` + `fetchWordsPage` + `fetchWordCount` |
| `.ea/spec/features.md` | **Modified** — documented typing mode spec |

## Features Implemented

- [x] Character-by-character input validation (green correct, red wrong)
- [x] Idle/Active state machine (any key activates, Esc/window blur deactivates)
- [x] Window focus detection via `NSApplication.didResignActiveNotification`
- [x] Sound effects: Tink (correct), Basso (wrong), Glass (complete) — pre-loaded NSSound
- [x] 5 hide modes: Show All / Vowels / Consonants / Random(40%) / All
- [x] 2 error modes: Retry Char / Reset Word
- [x] Word order: Sequential / Shuffle
- [x] Accent: US / UK (Youdao API type parameter)
- [x] Loop pronunciation (3s interval)
- [x] All settings persisted to UserDefaults
- [x] Chapter system (20 words/ch, progress persisted per book)
- [x] Live stats bar: Time / WPM / Inputs / Correct / Accuracy / Mistakes
- [x] Chapter complete page: stats summary + word list (errors first) + actions
- [x] Word list popover with clickable jump
- [x] Prev/Next word preview (clickable)
- [x] Full word card overlay (Space key)
- [x] Auto-pronunciation on new word
- [x] DB logging: typingLog table (wordId, bookId, mistakes, duration, mode, timestamp)
- [x] Keyboard shortcuts (⌘R replay, Tab cycle mode, ←→ nav, Esc pause)
- [x] Focus management: no visible focus ring, auto-refocus after popover

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Letters | Input spelling |
| Space | Show/hide word card |
| ⌘R | Replay pronunciation |
| Tab | Cycle hide mode |
| ← / → | Go back / Skip |
| Esc | Pause → idle (second press exits) |
| Return | Advance after word complete |

## Acceptance

- [x] Typing tab is independent from Flashcard tab
- [x] Settings persist across sessions
- [x] Sound plays on each keystroke (correct=Tink, wrong=Basso)
- [x] Pauses on window lose focus, resumes on keypress
- [x] Chapter progress remembered per book
- [x] `xcodebuild build` succeeds
