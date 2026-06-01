---
id: erudite-31
title: "Library: unit picker as a slice; drop two-mode toggle"
status: done
priority: high
estimate: M
---

## Objective

User feedback after living with erudite-29's `[Words | Chapters]`
segmented toggle:

> "Chapters" 模式下我看不到每个 Unit 的概况（从 xxx 到 xxy），只能"盲选"。
> 而且和 "Words" 模式下的检查 UI 不一致 —— 默认在 Library 里面应该是看
> words，进入 Typing/flashcard 练习模式可以作为两个按钮的入口，而非
> 现在两套交互模式。

The two-mode toggle was a wrong abstraction. Library's job is to be
"the place where you browse this app's words." Everything else is a
**slice** on that list:

- Book is a slice (which book / all books)
- State is a slice (All / New / Learning / Review)
- Sort is a slice ordering
- Search is a cross-cutting filter
- **Unit should also be a slice**, not a parallel "view"

Practice (Flashcard / Typing) is an **action** on the current slice,
not a separate mode.

## Deliverables

### A. WordSort cleanup (data layer)

- Removed `WordSort.dueDate` — Plan's `[Today][Tomorrow][This Week]`
  tabs surface this directly. Library's variant duplicated it.
- Removed `WordSort.lapses` — Today's recap (needsWork via
  Again/Hard/mistakes) is the proper home for "what should I
  revisit." A global lapses sort across the whole library no
  longer earns its place.
- Removed `summary.lapses` trailing in `WordSummaryRow` (no sort
  case references it anymore).

### B. `fetchUnitRanges(bookId:unitSize:)` + `UnitRange`

- New struct on DatabaseService: `UnitRange { index, firstSpelling,
  lastSpelling, count }`. Sendable + Hashable + Identifiable.
- Convenience: `label` ("Unit 5"), `rangeText` ("efflorescent — embellish").
- One SQL pass over the book's spellings in sortOrder, then chunk
  in Swift. Cheap (~13K rows × one column) and the chunk pass
  keeps it readable.

### C. Pagination removed

- `fetchWordSummaries(..., limit:)` is now `Int? = nil`. Library
  passes `nil` — the full matching slice loads, SwiftUI List
  recycles rows lazily.
- `LibraryState`: removed `totalAll` and `loadedCount`.
- `LibraryView`: removed `loadMore()` and the "Load More" button
  in the footer.
- Why: pagination + jump-bar were two overlapping "position"
  mental models. Eliminating one resolves the conflict.

### D. Unit picker (header)

- New picker between Book and State, only mounted when a Book
  is selected. Options: "All units" + per-unit rows
  ("Unit 1 (aback — apparel)").
- Selecting Unit ≠ All:
  - Hides the State + Sort pickers
  - Forces SQL state filter to `.all` and sort to `.bookOrder`
- A-Z jump bar visible only when `sort == .alphabetical` (was
  always-on before; meaningless under Book Order).
- `jumpToLetter` no longer auto-flips sort; it just selects the
  matching row and lets List auto-scroll.

### E. Footer split: bookFooter vs unitFooter

- **bookFooter** (no unit selected): "Showing N" status text only.
- **unitFooter** (unit selected): unit's `rangeText` on the left,
  `[▭ Flashcard]` `[⌨ Typing]` direct-start buttons on the right.
  Below: progress chips for Mastered / Review / Learning / New
  derived from `summaries.cardState`.
- Buttons build the unit via `StudyQueueBuilder.buildChapterUnit`
  and call `appState.startUnit(unit, in: .flashcard / .typing)`.
  **No UnitPreview detour** — the user just saw the words in the
  list, no second "preview" needed.

### F. LibraryState reshape

- Removed `viewMode: LibraryViewMode` and the entire enum.
- Added `selectedUnitIndex: Int?` (nil = "All units").
- Added `unitRanges: [DatabaseService.UnitRange]` — cached for
  the active book; refreshed on book / unitSize change.

### G. chaptersListPane removed

- Entire `chaptersListPane` view + `chapterRow` helper deleted
  (was the whole "Chapters mode" UI).
- `chapterPreviewUnit` @State + the `.sheet(item:)` binding
  removed. Unit study now goes via the footer buttons → AppState
  → tab switch, not a sheet.

## Files

### Modified

- `Erudite/Erudite/Models/WordSummary.swift` — drop `.dueDate` /
  `.lapses` cases; add provenance comment for the removal.
- `Erudite/Erudite/Services/DatabaseService.swift` —
  `fetchUnitRanges` + `UnitRange` struct; `fetchWordSummaries`
  takes `limit: Int?`; `buildSummaryQuery` honors nil limit and
  drops the dueDate/lapses ORDER BY branches.
- `Erudite/Erudite/Views/Components/WordSummaryRow.swift` — drop
  the dueDate/lapses trailing branches.
- `Erudite/Erudite/App/LibraryState.swift` — drop `viewMode` +
  `LibraryViewMode` enum; drop `totalAll` + `loadedCount`; add
  `selectedUnitIndex` + `unitRanges`.
- `Erudite/Erudite/Views/Library/LibraryView.swift` — full
  rewrite of header / footer / loading. Drops chaptersListPane,
  chapterPreviewUnit, loadMore, sort-flip-on-jump.

### Specs / docs

- `.ea/spec/features.md` — Library section rewritten around the
  one-list-with-slices model.
- `.ea/spec/lessons.md` — entries on
  (1) modes are usually wrong abstractions for slices,
  (2) action buttons in the footer eliminate "what will study consume?"
      cognitive question,
  (3) jump-bar belongs to alphabetical sort, not to Library at large.

## Verification

- `xcodebuild` clean across all 3 implementation commits.
- Unit picker labels match `fetchUnitRanges` output.
- Unit selection hides State + Sort; State+Sort reappear when
  switching back to "All units."
- Footer buttons land in Flashcard / Typing on the chosen unit
  (verified path: `buildChapterUnit` → `startUnit` → tab switch).
- A-Z jump bar appears only under .alphabetical sort.
- 13K-row List renders without jank (List virtualization handles it).

## Acceptance criteria

- [x] Drop `[Words | Chapters]` segmented toggle entirely
- [x] Unit picker in header (Book selected → visible; "All units" default)
- [x] Unit ≠ All hides State + Sort pickers
- [x] A-Z jump bar visible only under alphabetical sort
- [x] Footer buttons start unit study without UnitPreview
- [x] Pagination removed; SwiftUI List handles 13K rows
- [x] Sort cases reduced to `.bookOrder` and `.alphabetical`
- [x] Build clean
