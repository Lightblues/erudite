---
id: erudite-30
title: "Today activity strip + Plan as single scroll"
status: done
priority: medium
estimate: S
---

## Objective

Two pieces of feedback from the user:

1. **Today should show "what I did today"** — units studied
   (Flashcards / Typings) and words touched (reviewed / new).
   Data layer should own all the logic; the view just renders.
2. **Plan's two-region layout (erudite-29) was wrong** — the
   overview header (Roadmap + 7-Day Workload chart) is preview
   data the user glances at once per visit. Pinning it wasted
   screen real estate when the worklist was the actual
   destination. Should be one scroll: chart can scroll out of
   the way, word list takes the full viewport.

## Deliverables

### A. `TodayActivityStats` API + `fetchTodayActivityStats()`

- New nonisolated struct on DatabaseService:
  - `flashcardSessions: Int`
  - `typingSessions: Int`
  - `wordsReviewed: Int`
  - `newWordsLearned: Int`
  - `isEmpty: Bool` convenience
- `fetchTodayActivityStats()` since local-day start:
  - Sessions inferred via timestamp gap clustering (30-min
    threshold). No explicit session start/end rows in the DB.
    Two ratings 5 min apart = same session; 45 min apart = two.
  - `wordsReviewed` = COUNT DISTINCT wordId on reviewLog →
    reviewCard join.
  - `newWordsLearned` = COUNT DISTINCT wordId where
    reviewLog.state == 0 (i.e. the rating was given on a card
    that was `.new` at the time → bootstrap rating).
- Private `clusterCount(_:gap:)` helper — testable in isolation
  if we ever add unit tests.

### B. Today activity strip

- Inline strip placed between bookProgress and homeworkSection.
- Four chips with mode-tinted icons + count + label:
  - Flashcards (purple, rectangle.on.rectangle)
  - Typings (indigo, keyboard)
  - Reviewed (orange, arrow.clockwise)
  - New (blue, plus.circle)
- Vertical Divider between session counts and word counts so
  the two semantic groups read distinctly.
- Trailing "N sessions" total in tertiary type.
- Hidden when `isEmpty` — first launch of the day shows nothing,
  which is correct: the strip is a journal of what happened,
  not a placeholder.

### C. Plan single ScrollView

- Reverts erudite-29's `overviewHeader` wrapper. Title + Roadmap
  + Chart + Tab Bar + Worklist now all live in one ScrollView.
- Removed inner ScrollView from worklistList — nesting two
  ScrollViews breaks lazy row recycling and confuses scroll
  state. LazyVStack alone handles row recycling; the parent
  owns the scroll. Empty state gets `minHeight: 200` so it
  doesn't collapse to nothing inside the outer scroll.
- Internal padding cleanup: tab bar's outer 24pt horizontal
  padding removed (parent VStack already provides it); row
  content's `padding(.horizontal, 16)` removed for the same
  reason.

## Files

### Modified

- `Erudite/Erudite/Services/DatabaseService.swift` —
  `TodayActivityStats` struct, `fetchTodayActivityStats`,
  `clusterCount` helper
- `Erudite/Erudite/Views/Main/TodayView.swift` — `activityStats`
  state, `activityStrip(_:)` view, `activityChip(...)` helper,
  reload populates stats
- `Erudite/Erudite/Views/Plan/PlanView.swift` — single ScrollView
  layout, drop overviewHeader wrapper, drop inner ScrollView,
  internal padding cleanup

### Specs / docs

- `.ea/spec/features.md` — Today gets activity strip note;
  Plan reverts to single-scroll description.
- `.ea/spec/lessons.md` — entries on "preview vs always-actionable"
  decides fixed vs scrollable, and "data API surface owns the
  semantics" (cluster gap, state==0 detection) so views stay
  presentational.

## Verification

- `xcodebuild` clean across all 3 commits.
- Activity strip hides on a 0-everything day, shows on a day with
  any of the four counters > 0.
- Plan now scrolls as one document; user can scroll the chart out
  of view and let the worklist take the whole viewport.
- LazyVStack still recycles rows even without an inner ScrollView
  (the outer one handles scroll-position tracking).

## Acceptance criteria

- [x] DB API: `fetchTodayActivityStats` returns 4 numbers + isEmpty
- [x] DB API: sessions clustered by 30-min timestamp gap
- [x] DB API: newWordsLearned uses reviewLog.state == 0
- [x] Today: activity strip rendered between progress & homework
- [x] Today: strip hidden when all-zero
- [x] Plan: single ScrollView (chart scrolls with worklist)
- [x] Plan: no nested ScrollViews
- [x] Build clean
