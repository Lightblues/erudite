---
id: erudite-27
title: "Unit-driven study: StudyUnit + UnitPreview + Today selector + Typing→FSRS"
status: done
priority: high
estimate: M
---

## Objective

Three converging problems in the existing study flow:

1. **Sub-units felt synthetic.** Flashcard's "every 12 cards → unit
   summary" was a UX layer slapped on a pre-existing queue. Users couldn't
   preview a unit before committing, couldn't see which 12 words they
   were about to study, couldn't pick a path other than "Start Learning".
2. **Today/Plan/Flashcard had three separate SQL queries** for "what's
   due / what's new". Querying drift would silently break consistency
   between the preview and the actual session.
3. **Typing was an island.** A successful typed word emitted nothing
   to FSRS; the same word stayed at the front of the Flashcard queue
   tomorrow. Typing was a pure muscle drill, divorced from scheduling.

## Deliverables

### A. `StudyUnit` (domain object)
- New `Engine/StudyUnit.swift`: resolved cards + words + title + subtitle
  + estimatedMinutes + kind (.reviews / .newWords / .mix /
  .bookChapter(bookId, index)).
- Built up-front so consumers don't requery during the loop.
- `kind.icon` + `kind.color` (model-side ColorName enum to avoid SwiftUI
  imports in /Engine).

### B. `StudyQueueBuilder` (the only place that builds units)
- `buildTodayUnits(bookId, unitSize)`: due → `unitSize`-card chunks +
  optional New Words unit (cap = unitSize). Reuses existing
  `fetchDueCards` + `fetchNewCards` + `fetchWords(ids:)`.
- `buildChapterUnit(bookId, chapterIndex, chapterSize)`: book-driven
  unit; defensively synthesizes a `state=.new` card for any word missing
  a reviewCard so the unit can still be consumed.
- Pure builder, no @MainActor — testable in isolation.

### C. `AppSettings` (process-wide knobs)
- `unitSize` lives here (default 12, range 5–30, persisted as
  `study.unitSize`). Single source of truth shared by Flashcard chunk,
  Book Chapter size, and Today's review slicer.
- Replaces the standalone `study_unitSize` key the StudyViewModel was
  reading directly (kept as compat read for now to migrate users).

### D. Today as Unit selector
- Replaced `[Start Learning][Review Due][Type Practice]` with a list of
  StudyUnit cards. Each row: icon + title + subtitle + chevron.
- "Today's plan" header + summary ("4 units · ~22 min").
- All-caught-up state when no units exist.
- Optional Book Chapter unit appended (chapter 0 of active book; future
  work: track per-book chapter progress).
- 2-column word preview retained below for "browse without committing".

### E. `UnitPreviewView` (the GRE-3000 paper-book moment)
- Sheet (not nav push) so the user can dismiss without leaving Today.
- Lists all 12 words with index + spelling + IPA + POS + Chinese def.
- Three actions: [Cancel] (Esc) / [Typing] / [Flashcard] (default,
  Return). Both Typing/Flashcard pin the unit to
  `appState.currentUnit` and switch to the corresponding tab.

### F. Study/Typing consume `StudyUnit`
- `AppState.currentUnit: StudyUnit?` + `startUnit(_:in:)`.
- `StudyViewModel.start(unit:database:)` and
  `TypingViewModel.start(unit:database:)`: install the unit's
  cards/words directly, set `inUnitMode/unitMode = true`, no SQL
  inside the view model.
- `StudyView.task` and `TypingView.task` consume `appState.currentUnit`
  on first appear (then clear it so a re-mount doesn't double-consume).
- In Flashcard's `inUnitMode`, the every-N-cards `.unitComplete`
  transition is disabled — the entire unit IS the session, exhausting
  the queue lands on `.complete` (which renders the same summary).

### G. Typing → FSRS derived rating
- New `applyDerivedFSRSRatingIfApplicable(mistakes:)` in TypingViewModel.
- mistakes → rating: 0 → Good, 1–2 → Hard, 3+ → Again.
- **Strict gate**: only fires when `unitMode == true`,
  `card.state != .new`, AND `card.dueDate <= now`. New cards must be
  bootstrapped via Flashcard reveal cycle; future-scheduled cards
  aren't pulled forward.
- Persists via `FSRSEngine.schedule` + `db.updateCard` +
  `db.insertReviewLog` so the same card's next Flashcard appearance
  reflects today's typing as if it had been a flashcard rating.

## Files

### Created
- `Erudite/Erudite/Engine/StudyUnit.swift`
- `Erudite/Erudite/Engine/StudyQueueBuilder.swift`
- `Erudite/Erudite/App/AppSettings.swift`
- `Erudite/Erudite/Views/Main/UnitPreviewView.swift`

### Modified
- `Erudite/Erudite/App/AppState.swift` — `settings`, `currentUnit`,
  `startUnit`, `UnitStudyMode`
- `Erudite/Erudite/Views/Main/TodayView.swift` — full unit-selector
  rewrite (replaces quickActions block); reload populates `todayUnits`
- `Erudite/Erudite/Views/Study/StudyViewModel.swift` —
  `start(unit:database:)`, `inUnitMode`, `activeUnit`, gated unitComplete
- `Erudite/Erudite/Views/Study/StudyView.swift` — `.task` consumes
  pinned unit
- `Erudite/Erudite/Views/Study/TypingViewModel.swift` —
  `start(unit:database:)`, `unitMode`, `activeUnit`, `engine`,
  `applyDerivedFSRSRatingIfApplicable`
- `Erudite/Erudite/Views/Study/TypingView.swift` — `.task` consumes
  pinned unit

### Specs / docs
- `.ea/spec/features.md` — Today section rewrite (Unit selector +
  preview); Flashcard 3g (two entry paths); Typing 3c (unit vs
  standalone, derived FSRS rating)
- `.ea/spec/lessons.md` — 3 new entries (three SQLs as smell, two view
  models converging on one shape, Typing→FSRS gate matters)

## Verification

- `xcodebuild build` clean, BUILD SUCCEEDED on every milestone.
- App launched, no crash. reviewCard distribution preserved across
  rebuild (`0=12991, 1=8, 2=112, 3=1`).
- `study.unitSize` defaults correctly to 12 without an explicit
  UserDefaults write (read path returns 0 → falls back to default).

## Acceptance criteria

- [x] Today shows StudyUnit cards instead of generic action buttons
- [x] Tapping a unit opens UnitPreviewView (sheet, dismissible)
- [x] [Flashcard] / [Typing] from preview pin the same unit and switch tabs
- [x] StudyView/TypingView consume the pinned unit on first appear
- [x] In Flashcard unit mode, exhausting the queue lands on .complete
      (no mid-session unitComplete checkpoint)
- [x] Typing in unit mode emits FSRS rating with strict state gate
- [x] Standalone Typing (open the tab directly) preserves existing
      chapter-browsing experience and does NOT touch FSRS
- [x] unitSize is the single source of truth (AppSettings); 12 default
- [x] Build + runtime smoke test pass
