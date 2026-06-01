---
id: erudite-28
title: "Unify study surfaces: Today=homework+recap, tab landings as picker, SessionSummaryView, Library Chapters"
status: done
priority: high
estimate: M
---

## Objective

Three sources of friction the user identified after using v3.0:

1. **Today conflated two mental models** — FSRS-driven homework and
   user-driven book browsing under one "Today's plan" header.
2. **Direct tab entry was inconsistent** — clicking Flashcard/Typing tabs
   without going through Today's UnitPreview ran a different code path
   (legacy mixed-queue / persisted chapter index) than picking a unit
   from Today.
3. **Three completion screens, three layouts** — Flashcard `.complete`,
   Flashcard `.unitComplete`, and Typing `chapterCompleteView` each
   answered "session over, how'd you do?" with different vocabulary
   and field names.

## Deliverables

### A. `UnitPickerView` shared component
- Pure rendering: takes `[StudyUnit]` + `onPick: (StudyUnit) -> Void`
  closure, owns no state.
- Header (default "Today's homework") + summary line ("4 units · ~22 min")
  + per-unit rows (icon + title + subtitle + chevron) + empty state.
- Used by Today (homework section), Flashcard tab landing, Typing tab
  landing — three call sites, identical experience.

### B. Today rewrite — homework + recap
- "Today's homework" section: FSRS-driven units only (Reviews · N + New
  words). Book Chapter shortcut **dropped** (moved to Library).
- "Today's recap" section: list of words touched today via reviewLog +
  typingLog, sorted by `pressingScore` (Again > Hard > many-mistakes >
  Good). Each row: badge ("Again" / "Hard" / "N miss") + spelling +
  Chinese def + attempt count if > 1. Tapping → popover with full word.

### C. `fetchTodayRecap` + `RecapEntry` (DatabaseService)
- Unions today's reviewLog (per word: latest rating + count) with today's
  typingLog (per word: total mistakes + attempts).
- Returns `[RecapEntry]` sorted by pressingScore. Word lookup via
  projection SQL — no full-Word JSON decode for the list.

### D. Tab landings as picker
- `StudyView`/`TypingView`: when entering without `appState.currentUnit`
  pinned, show `UnitPickerView` instead of running legacy queue load.
- `showingPicker: Bool` state flips false when a unit gets picked /
  pinned. KeyCaptureView is conditionally mounted so the picker's
  Buttons get their clicks (not eaten by the keyboard grabber).
- `onChange(of: currentUnit?.id)` covers the case where user pinned a
  different unit on Today while we were already on the tab.

### E. `SessionResult` + `SessionSummaryView` (unified summary)
- New domain shape `SessionResult { mode, unit, entries, durationSeconds,
  wpm }` with `Entry { word, rating?, mistakes, attempts }`.
- Computed aggregates: `totalCards`, `accuracy` (Hard = 0.5 credit),
  `againCount`, `sortedEntries` (worst-first).
- New view `SessionSummaryView(result:heading:primaryAction:secondaryAction:)`
  renders header + stat strip + word grid + actions. Mode-specific WPM
  surfaces conditionally.
- Replaces three bespoke completion layouts:
  - Flashcard `.complete` → SessionSummaryView with mode-aware action
    ("Study More" in legacy, "Back to Today" in unit mode)
  - Flashcard `.unitComplete` → SessionSummaryView with Continue/Stop
    (still per-unit slice for legacy chunking)
  - Typing `chapterCompleteView` → SessionSummaryView with Next/
    Repeat/Dictation actions (or "Back to Today" in unit mode)

### F. Library Chapters view
- New `LibraryViewMode` enum: `.words` (default) | `.chapters`.
- Header gains a segmented control when a Book is selected.
- Chapters mode lists chapter rows (size = `appState.settings.unitSize`).
- Tapping a chapter → `StudyQueueBuilder.buildChapterUnit` → opens
  `UnitPreviewView` as a sheet. Same Today→preview→Flashcard/Typing
  pipeline, just entered from Library instead.

## Files

### Created
- `Erudite/Erudite/Engine/SessionResult.swift`
- `Erudite/Erudite/Views/Components/UnitPickerView.swift`
- `Erudite/Erudite/Views/Components/SessionSummaryView.swift`

### Modified
- `Erudite/Erudite/App/LibraryState.swift` — `viewMode: LibraryViewMode`
- `Erudite/Erudite/Services/DatabaseService.swift` — `RecapEntry` +
  `fetchTodayRecap`
- `Erudite/Erudite/Views/Main/TodayView.swift` — homework section uses
  UnitPickerView; new recap section + RecapRow; reload populates recap;
  drops bookChapterUnit injection
- `Erudite/Erudite/Views/Library/LibraryView.swift` — viewMode segmented
  picker, `chaptersListPane`, chapter row → UnitPreview sheet
- `Erudite/Erudite/Views/Study/StudyView.swift` — `showingPicker`
  + `pickerLanding`; .complete and .unitComplete now SessionSummaryView
- `Erudite/Erudite/Views/Study/StudyViewModel.swift` — `sessionResult()`
  and `unitResult()` builders
- `Erudite/Erudite/Views/Study/TypingView.swift` — `showingPicker` +
  `pickerLanding`; chapterCompleteView → SessionSummaryView
- `Erudite/Erudite/Views/Study/TypingViewModel.swift` — `sessionResult()`

### Specs / docs
- `.ea/spec/features.md` — Today rewrite (homework+recap two-fold
  responsibility, book chapters moved to Library)
- `.ea/spec/lessons.md` — 4 new entries (3 layouts converging on one
  shape, Today's two responsibilities don't belong together, tab
  landing without state should pick not default, recap as cheap big win)

## Verification

- `xcodebuild` clean across all milestones.
- App launched without crash. Live DB has reviewLog (68 today) +
  typingLog (26 today), so the recap section will populate immediately
  on first run.
- Empty Flashcard / Typing tab now shows UnitPickerView instead of
  silently running legacy queue.
- Library segmented control appears only when a Book is selected.
- Three entry paths to UnitPreview converge: Today homework → preview;
  Library chapter → preview; tab picker → direct start (no preview
  since user already on the tab).

## Acceptance criteria

- [x] Today: homework section is FSRS-only; book chapters not present
- [x] Today: recap section shows touched words, sorted "needs work" first
- [x] Library: Words/Chapters segmented control when a book is picked
- [x] Library: chapter row → UnitPreview → Flashcard or Typing
- [x] Empty Flashcard / Typing tabs show UnitPickerView
- [x] All three completion screens render via SessionSummaryView
- [x] Build clean and runtime smoke-tested
