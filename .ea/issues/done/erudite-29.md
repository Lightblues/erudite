---
id: erudite-29
title: "Recap as practice mode + Plan as tab-segmented worklist"
status: done
priority: high
estimate: M
---

## Objective

Two friction points the user identified after living with v3.1:

1. **Today's recap was read-only.** Users could see "what I touched
   today" + "how I did," but the natural follow-up — "let me re-drill
   the ones I missed" — required no UI path. The recap section was a
   mirror, not a tool.
2. **Today and Plan overlapped.** Today's two-column preview showed
   the next 50 due + next 50 new words, which is exactly what Plan's
   New Words Queue + Due Backlog already showed. And Plan stacked
   four sections in one ScrollView, so getting to "Tomorrow" required
   scrolling past the workload chart every time.

Underlying realization: **Today and Plan answer different questions.**
Today = "today only" (do + did + redo). Plan = "节奏 / 全局" (overview
+ all upcoming worklists). Removing the overlap clarifies both.

## Deliverables

### A. `StudyUnit.Kind.recap` + skip-FSRS gate (engine)

- New case `recap` on `StudyUnit.Kind` with its own pink color slot
  and `arrow.uturn.left.circle.fill` icon.
- New computed `Kind.skipsFSRSWriteback: Bool` — true only for
  `.recap`. Single source for "is this a practice unit?"
- `StudyViewModel.rate` checks the gate and skips
  `db.updateCard` + `insertReviewLog` when set. Stats and
  `reviewResults` still populate so SessionSummary renders.
- `TypingViewModel.applyDerivedFSRSRatingIfApplicable` returns early
  on the same gate before fetching a card — recap typing never
  emits a derived rating.

### B. `StudyQueueBuilder.buildRecapUnit(from: [RecapEntry])`

- Materializes a hand-picked subset of today's recap into a
  `.recap`-kind unit. Pulls each word's reviewCard (or synthesizes a
  fresh `.new` card if missing) so the same Flashcard/Typing
  pipeline consumes it. Order preserved from caller — Today sorts
  by pressingScore, so "worst first" carries through to study.

### C. `RecapEntry.needsWork` (DatabaseService)

- New computed: true iff `latestRating == .again || .hard ||
  typingMistakes > 0`. Used by Today as the default selection set
  for the recap multi-select.

### D. Today rewrite — drop preview, recap as operation panel

- Removed the two-column "Reviews | New" preview block (~80 lines
  + two SQL fetches). That data lives on Plan now.
- Recap section gains a checkbox per row, default-checked for
  `needsWork` rows.
- Header changes from "8 words · 3 need work" to "K / N selected" —
  language now tracks the operation rather than the read.
- Bottom row: `[Re-review · K]` primary CTA (pink-tinted, mode-
  matching) + `[Select needsWork]` secondary that only surfaces
  when the user's selection has diverged from the default.
- Tapping the CTA materializes the selection and opens the same
  `UnitPreviewView` sheet homework rows use.

### E. Plan tab-segmented worklist

- Layout split: top region (Roadmap + 7-Day Workload chart) is
  fixed and always visible. Bottom region is a tab bar +
  full-height scrollable list.
- New `WorklistTab` enum (private to PlanView): `.today`,
  `.tomorrow`, `.thisWeek`, `.later`, `.new`. Each tab carries a
  colored count chip in the tab bar.
- Mapping:
  - `.today` merges `DueBucket.overdue + .today`. Overdue rows
    are flagged inline with a red exclamation marker so the user
    still notices them inside the merged tab.
  - `.tomorrow` / `.thisWeek` / `.later` are 1:1 with DueBucket.
  - `.new` shows `fetchNewWordSummaries(limit: 50)` (was the old
    standalone "New Words Queue" section).
- Disclosure-group "Due Backlog" deleted; one tab per bucket
  replaces the disclosure tree.
- `perBucketLimit` bumped 30 → 100 to fill a single-tab viewport.

## Files

### Modified

- `Erudite/Erudite/Engine/StudyUnit.swift` — `.recap` kind, pink
  ColorName, `skipsFSRSWriteback` flag
- `Erudite/Erudite/Engine/StudyQueueBuilder.swift` — `buildRecapUnit`
- `Erudite/Erudite/Services/DatabaseService.swift` — `RecapEntry.needsWork`
- `Erudite/Erudite/Views/Components/UnitPickerView.swift` — `.pink` case
- `Erudite/Erudite/Views/Main/UnitPreviewView.swift` — `.pink` case
- `Erudite/Erudite/Views/Study/StudyViewModel.swift` — skip-FSRS gate in `rate()`
- `Erudite/Erudite/Views/Study/TypingViewModel.swift` — skip-FSRS gate in derived rating
- `Erudite/Erudite/Views/Main/TodayView.swift` — drop preview;
  recap multi-select + Re-review CTA + recapSelection state
- `Erudite/Erudite/Views/Plan/PlanView.swift` — overview header
  fixed at top; segmented WorklistTab + per-tab list

### Specs / docs

- `.ea/spec/features.md` — Today and Plan sections rewritten
- `.ea/spec/lessons.md` — 3 new entries (recap as operation panel;
  Today and Plan have separable mental models; tab-segment beats
  one-scroll for divergent worklists)

## Verification

- `xcodebuild` clean across all 3 implementation commits.
- Recap CTA disabled when no rows selected; enabled with the
  needsWork count visible by default.
- Re-review session ratings DO populate SessionSummary but DO NOT
  modify reviewCard.dueDate (verified via gate path in
  `StudyViewModel.rate` and `TypingViewModel.applyDerivedFSRSRatingIfApplicable`).
- Plan top region stays put when switching tabs; only the list
  region rebinds.
- Today tab in Plan shows overdue rows with red marker prefix.

## Acceptance criteria

- [x] Today: two-column preview removed
- [x] Today: recap rows have checkboxes; default = needsWork
- [x] Today: [Re-review · K] CTA materializes a `.recap` unit
- [x] Today: [Select needsWork] reset surfaces when selection diverges
- [x] Engine: `.recap` units skip FSRS writeback in both ViewModels
- [x] Plan: top region fixed (Roadmap + 7-Day Workload always visible)
- [x] Plan: tab bar with [Today][Tomorrow][This Week][Later][New]
- [x] Plan: each tab shows count chip + scrolls independently
- [x] Build clean
