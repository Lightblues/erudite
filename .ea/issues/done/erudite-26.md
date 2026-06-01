---
id: erudite-26
title: "Library v3: resizable split, persistent state, A-Z jump bar; Flashcard Unit chunking; integrity diagnostics"
status: done
priority: med
estimate: M
---

## Objective

Three categories of polish following daily use of the v2 surfaces:

- **Library UI**: 50/50 split was hard to scan; tab-switching reset
  position; no fast way to jump to a letter.
- **Flashcard UX**: 100+ word sessions felt overwhelming. The traditional
  word-book "unit" model (10–15 words → checkpoint → continue) maps
  cleanly onto FSRS without modifying the engine.
- **Diagnostics**: After v3.0 upgrade, no easy way to verify the DB is
  internally consistent or to spot stale rows (e.g. cached words missing
  reviewCards).

## Deliverables

### A. Library: resizable Mail-style split
- Replaced 50/50 split with **Mail-like proportions**: list defaults to
  360pt, draggable 280–600pt via a hit-region inside the divider, soft
  upper bound = `totalWidth - 360` so detail pane always has ≥360pt.
- Width persisted to `UserDefaults` (`library.listPaneWidth`).
- Implementation: `ResizableDivider` View with `NSCursor.resizeLeftRight`
  hover and `DragGesture`.

### B. Library: persistent view state (`LibraryState` singleton)
- All "live state" (loaded summaries, pagination offset, selection,
  filter pickers, search text, list pane width, available letters) moved
  to `LibraryState` (@Observable) owned by `AppState`.
- `LibraryView` now reads via `@Bindable var lib = appState.libraryState`
  so tab-switching no longer wipes the user's place.
- `.task` only seeds on first appear (`didInitFromAppState` flag);
  subsequent appears just verify the state isn't empty.

### C. Library: A-Z jump bar
- Vertical 16pt-wide strip between list pane and divider.
- `DatabaseService.offsetForFirstSpelling(startingWith:...)` uses the
  same WHERE clauses as the main summary query so the jump respects all
  active filters.
- Letters with zero matches under current filters are dimmed
  (`availableStartingLetters` populates `LibraryState.availableLetters`
  on every reload).
- Clicking a letter forces `WordSort.alphabetical` if not already, then
  reloads a page starting at the computed offset.

### D. Library: Mnemonic icon → user-mnemonic indicator
- After v3.0, builtin mnemonics are at ~100% coverage so the yellow
  lightbulb icon had no signal value.
- Added `WordSummary.hasUserMnemonic` populated via
  `EXISTS (SELECT 1 FROM user_content uc WHERE uc.wordId=w.id AND uc.type='mnemonic')`
  in the projection SQL.
- Row icon flipped to **purple lightbulb only when user has authored a
  mnemonic** for the word.

### E. Library: Reps/lapses trailing labels
- `WordSummary.reps` and `WordSummary.lapses` now projected from the
  reviewCard (`rc.reps`, `rc.lapses`) into the summary SELECT.
- `WordSummaryRow` accepts a new `trailingForSort:` parameter that auto-
  derives the trailing label from the active sort:
  - `Due Date` → relative due ("today" / "1d late" / "in 3d")
  - `Most Lapses` → "L:N"
  - `bookOrder` / `alphabetical` → no trailing
- Lets the row tell the user *why* it's where it is in the list.

### F. Flashcard: Unit chunking + Unit Summary card
- New `Phase.unitComplete` between `studying` and `complete`.
- `unitSize` defaults to 12 (persisted as `study_unitSize`).
- Mix is "reviews first, then new" (already the queue order: due cards
  come from `fetchDueCards`, new cards appended via `fetchNewCards`).
- After every `unitSize` ratings:
  - `cardsThisUnit` increments inside `rate()`.
  - At unit boundary: stop loop pronunciation, push current to history,
    transition to `.unitComplete`.
  - `continueAfterUnit()` resets per-unit counters and pulls the next
    card without double-pushing history.
- Unit Summary view: header ("Unit N complete"), 4 stats (Cards / Time /
  Accuracy / Again), word mini-grid colored by rating, [Continue]
  (default action; Space/Return/click) and [Stop].
- Esc / Q from `.unitComplete` ends the session.
- **FSRS unchanged.** All scheduling persists inside `rate()` before the
  unit boundary check; an interrupted unit loses no progress.

### G. DataDiagnosticsView: DB integrity checks
- New `IntegrityReport` from `DatabaseService.checkIntegrity()`:
  - orphan reviewCards / wordListEntry / user_content (FK violations)
  - words without a reviewCard
  - non-new cards without any reviewLog
  - words missing chinese def / builtin mnemonic
  - words NOT tagged `ai_enriched`
- Renders as a third section in the Data tab (Debug Panel ⌘⇧D), with
  green "OK" for zero, red for "should be zero but isn't", orange for
  informational counts.

## Files

### Created
- `Erudite/Erudite/App/LibraryState.swift` — @Observable singleton

### Modified
- `Erudite/Erudite/App/AppState.swift` — added `libraryState` field
- `Erudite/Erudite/Models/WordSummary.swift` — added `hasUserMnemonic`,
  `reps`, `lapses`
- `Erudite/Erudite/Services/DatabaseService.swift`:
  - `offsetForFirstSpelling`, `availableStartingLetters` (jump bar)
  - `IntegrityReport` + `checkIntegrity()`
  - SELECTs add `hasUserMnemonic`, `reps`, `lapses` columns
  - typed `rowToSummary` reads
- `Erudite/Erudite/Views/Library/LibraryView.swift` — full rewrite around
  `LibraryState`; resizable split; A-Z jump bar; trailing-for-sort plumbing
- `Erudite/Erudite/Views/Components/WordSummaryRow.swift` — `trailingForSort:`
  param, `resolvedTrailing` derivation; lightbulb → user-mnemonic
- `Erudite/Erudite/Views/Study/StudyViewModel.swift` — Unit chunking
  (`Phase.unitComplete`, `unitSize`, `cardsThisUnit`, `unitResults`,
  `unitsCompleted`, `continueAfterUnit`)
- `Erudite/Erudite/Views/Study/StudyView.swift` — `unitCompleteState` view +
  keyboard handlers for `.unitComplete`
- `Erudite/Erudite/Views/Debug/DataDiagnosticsView.swift` —
  `integritySection` rendering

### Specs / docs
- `.ea/spec/features.md` — Library resizable split + persistent state +
  A-Z jump bar + lightbulb meaning; Flashcard Unit state machine + Unit
  Complete card + key bindings
- `.ea/spec/data.md` — added jump-bar query methods + `checkIntegrity`
  to method table
- `.ea/spec/lessons.md` — 5 new entries (tab-reset @State, [Character]
  ForEach, foregroundStyle ternary typing, FSRS×Unit orthogonality,
  diagnostics paying for themselves)

## Verification

- `xcodebuild` clean, BUILD SUCCEEDED.
- App launched, no crash.
- Live DB integrity SQL spot-checked against `checkIntegrity()` output:
  - 0 orphan reviewCards / wordListEntry rows ✓
  - 29 cached words without reviewCard / chinese def / mnemonic — these
    are runtime API-cached lookups that bypass the seed flow; the
    diagnostics view now surfaces this so we can fix it later.
  - 3,817 words not tagged `ai_enriched` (pre-AI seed leftovers).
- `EXPLAIN QUERY PLAN` confirms jump-bar offset uses index `idx_card_word`.

## Acceptance criteria

- [x] Library list is narrow (Mail-style) by default; user-resizable
- [x] Tab-switching to Library and back preserves position, selection,
      filters
- [x] A-Z jump bar with dim/active letter states
- [x] Lightbulb only appears for user-authored mnemonics
- [x] Reps/lapses-aware trailing labels
- [x] Flashcard: 12-card units; Unit Complete card with [Continue][Stop]
- [x] Esc / Q from .unitComplete ends session
- [x] Diagnostics view shows DB integrity checks with red/green status
- [x] Build clean, runtime smoke-tested
