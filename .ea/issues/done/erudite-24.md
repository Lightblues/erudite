---
id: erudite-24
title: "Word Management: Today preview, Plan tab, Library split, WordDetail editing"
status: done
priority: high
estimate: L
---

## Objective

Make word management visible and keyboard-driven across the app:

- Today's plan should *show what's queued*, not just count it.
- Library should browse 13K words without lag and support keyboard scanning.
- WordDetail should expose the database — FSRS state, review history, books — and let users add their own mnemonics.
- The user should be able to see future workload, not just today's.
- Popovers should be a true "peek" — never disrupt active study sessions.

## Context

The previous Today/Library/WordDetail surfaces stopped at "list the data". Three pain points emerged in real use:

1. Library loaded all 13K words as full `Word` JSON blobs and filtered in Swift. Inputting a search character re-scanned the array four times per frame (the four `.filter{}.count` calls in the tier picker).
2. WordDetail showed only the bundled fields, with no path to the user's own learning state or annotations.
3. There was no view of *future* workload — only the current `dueCount` integer on Today.

A second wave of issues came up while wiring keyboard interaction:

4. The popover Esc handler I first added (via `.onKeyPress(.escape)`) needed focus, which popovers don't reliably hand out — Esc silently failed.
5. A first attempt to coordinate popover/host keyboards by short-circuiting `KeyCaptureView.keyDown` while a popover was up *dropped* every key, locking the keyboard whenever popoverDepth got stuck above zero.
6. The first "Open in Library" button switched tabs, killing in-progress Typing/Flashcard sessions.

## Delivered

### 1. SQL-driven WordSummary projection (Library + Today + Plan)

- `Models/WordSummary.swift` — lightweight projection (id, spelling, phonetic, frequency, first def, POS, hasMnemonic, cardState, dueDate). Read-only; never persisted.
- `WordSort` (frequency / alphabetical / dueDate / lapses) and `WordStateFilter` (all / new / learning / review / mature).
- `DatabaseService.fetchWordSummaries(book, tier, state, search, sort, limit, offset)` and `fetchWordSummaryCount(...)` — single private `buildSummaryQuery()` helper composes the SQL.
- `json_extract(data, '$.definitions[0].chinese')` pulls the first definition directly from the JSON BLOB; `LEFT JOIN reviewCard` surfaces card state in the same query. Search runs as `LIKE` on spelling and first definition.
- Library debounces search at 300ms, paginates 200 at a time with a Load More button, and uses a shared `Views/Components/WordSummaryRow.swift` (compact + standard density).

### 2. Today: two-column preview

- Replaced the bulky StatBadge column + "All caught up!" card with a tight inline stat strip and a real two-column preview (Reviews | New) below the quick actions.
- Each row shows spelling + POS + first Chinese def; Reviews rows include a relative due-date label (`today` / `1d late` / `in 2d`) computed at local-day boundaries.
- Tapping a row opens a popover with the full `WordPopoverView`. Empty columns show inline "No reviews due" / "No new words queued" instead of a separate banner.
- New DB methods: `fetchDueSummaries(now, inBook, limit)`, `fetchNewWordSummaries(inBook, limit)`.

### 3. WordDetail: Learning Progress + user mnemonics

- New "Learning Progress" GroupBox at the top: state badge, due-date sentence, reps/lapses/accuracy/stability/difficulty stat blocks, recent rating tape (last 8 ratings as colored chips), and the books containing the word as chips.
- Mnemonics section now distinguishes builtin entries (yellow `lightbulb.fill`, locked) from user entries (purple `pencil.circle.fill`, editable + deletable). Add via the section's `[+ Add yours]` button → `MnemonicEditor` sheet.
- New `user_content` table: `(id, wordId, type, content, createdAt, updatedAt)`. The `type` column is generic so future user notes ship without schema migration.
- `escapeBehavior` parameter (`.push` | `.embedded`) controls whether Esc dismisses the page or leaves it to the host. `.push` mode mounts a hidden `Button.keyboardShortcut(.cancelAction)` so Esc works without focus tracking.
- New DB methods: `fetchReviewCard(forWord:)`, `fetchReviewLogs(cardId:limit:)`, `fetchBooks(containingWord:)`, plus `addUserContent` / `updateUserContent` / `deleteUserContent` / `fetchUserContent`.

### 4. Plan tab (new sidebar tab)

- Sidebar order is now Today / **Plan** / Flashcard / Typing / Library / Stats.
- Four sections, each independently fetched and rendered:
  - **Roadmap** — progress bar + ETA in days for the active book, with an "estimate varies with review accuracy" caveat.
  - **7-Day Workload** — Swift Charts `BarMark` bar chart of upcoming due-card load per day, value labels on top, snapshot disclaimer below.
  - **New Words Queue** — next 50 words by book sortOrder; rows are `NavigationLink(value: wordId)` into the full WordDetailView.
  - **Due Backlog** — DisclosureGroups for Overdue / Today / Tomorrow / This Week / Later, each with a per-bucket count and expand-to-list interaction. Today bucket bolded; Overdue rendered in red.
- New DB methods: `fetchDueCountsByDay(daysAhead, inBook)`, `fetchDueBacklog(inBook, perBucketLimit)`, `fetchDueBacklogCounts(inBook)` plus the `DueBucket` enum.
- AI `SystemPrompt` gets a context note for the new tab so the chat can reason about pacing.

### 5. Library Mail-style split layout

- `GeometryReader` switches between two layouts:
  - **Wide (≥ 900pt):** list on the left + full `WordDetailView` (escapeBehavior `.embedded`) in the right pane. `List(selection:)` makes ↑/↓ move selection automatically; Esc clears selection and returns to a "Select a word" empty pane.
  - **Narrow (< 900pt):** the original `NavigationStack` push, so windows squeezed by the AI panel still work.
- Selection drives a lazy `fetchWord(id:)` into `selectedFullWord` and reuses `WordDetailView` verbatim — no inline simplified version.

### 6. Popover keyboard model

- `AppState.popoverDepth` (`@ObservationIgnored`) tracks how many word popovers are visible; bumped in `onAppear` / `onDisappear` of `WordPopoverView` and `NotFoundPopoverView`.
- `KeyCaptureView` always forwards `keyDown` events (events are never dropped); only the focus tug-of-war is suspended — `resignFirstResponder` and `windowDidBecomeKey` skip the re-grab while `popoverDepth > 0`. This fixes the bug where Esc inside a popover also paused the host flashcard/typing session.
- All popover and `WordDetailView` Esc handling uses a hidden `Button.keyboardShortcut(.cancelAction)` rather than `.onKeyPress(.escape)` — no focus dependency, works reliably inside ScrollViews and popovers.
- "Show details" footer button (formerly "Open in Library") in `WordPopoverView` calls `AppState.showWordDetailSheet(wordId)`. `ContentView` mounts a global modal sheet that hosts a `NavigationStack { WordDetailView(.push) }` — surfaces the full detail view on top of the current tab without disrupting the active study session. Cmd+O bound; Esc / [Done] dismisses.
- `WordPopoverHost` enum (`.elsewhere | .library`) hides the redundant "Show details" button when the popover is opened inside Library (the right-hand pane already shows the same content).

## Files Created (4)

- `Models/WordSummary.swift` — projection + sort + state-filter enums
- `Views/Components/WordSummaryRow.swift` — shared row, two density modes, `DueDateFormatter` helper
- `Views/Plan/PlanView.swift` — the four-section Plan tab
- `Views/Library/WordDetailView.swift` (rewritten) — Learning Progress + user mnemonics + escapeBehavior

## Files Modified (significant)

- `App/AppState.swift` — `popoverDepth`, `popoverDidAppear/Disappear`, `detailSheetWordId`, `showWordDetailSheet(_:)`, plus the new `.plan` SidebarTab case
- `Services/DatabaseService.swift` — `user_content` schema; WordSummary queries; due/new/workload/backlog queries; word-centric reviewCard/log/book queries
- `Views/Library/LibraryView.swift` — split + narrow layouts, debounced search, state filter, sort picker, `WordDetailLoader`, hidden-Button Esc on the list
- `Views/Components/WordPopoverView.swift` — host enum, popover-depth registration, Esc via `.keyboardShortcut(.cancelAction)`, "Show details" + Cmd+O
- `Views/Components/KeyCaptureView.swift` — `popoverDepth`-aware focus re-grab (events never dropped)
- `Views/Main/ContentView.swift` — global detail sheet, sidebar order
- `Views/Main/TodayView.swift` — two-column preview
- `Services/AI/SystemPrompt.swift` — `.plan` context note

## Bugs Fixed Along the Way

- **NavigationStack missing in detail column** — `LibraryView` and `PlanView` rows used `NavigationLink(value:)` but `NavigationSplitView`'s detail column doesn't supply its own stack. Wrapped each list view in its own `NavigationStack`. (Caught only after running the app — a "trust but verify" reminder.)
- **`.focusable() + .onKeyPress(.escape)` was unreliable inside popovers and ScrollViews.** Replaced everywhere with the hidden-Button + `.keyboardShortcut(.cancelAction)` pattern. The Button is part of the view tree so the shortcut is installed for as long as the view is visible — no focus required.
- **`KeyCaptureView.keyDown` returning early on `popoverDepth > 0` swallowed every key.** When the popover lifecycle didn't fire `onDisappear` cleanly, depth got stuck above zero and the keyboard locked. Reverted to always-forward; only the focus re-grab in `resignFirstResponder` / `windowDidBecomeKey` is now popover-aware.
- **"Open in Library" killed Typing/Flashcard sessions.** Switching tabs fired `onDisappear` on the host. Replaced with a modal sheet so the host stays alive.

## Acceptance

- [x] Today shows the next reviews and new words side-by-side; tapping a row opens a popover.
- [x] Plan tab shows a roadmap, 7-day chart, next-50 queue, and due backlog by bucket.
- [x] Library opens to a split list+detail when wide enough, falls back to push navigation when narrow. ↑/↓ move selection.
- [x] WordDetail shows FSRS state, recent ratings, and books; user can add/edit/delete their own mnemonics.
- [x] Esc dismisses popovers without pausing flashcard study; Esc dismisses pushed `WordDetailView`s.
- [x] Cmd+O on a popover opens the full word in a sheet without leaving the current tab.
- [x] `xcodebuild build` succeeds clean.

## Notes

- WordSummary intentionally introduces a "data path fork": list views read summaries (~7 columns from SQL projection); detail views read full Word (`fetchWord(id:)`). This is the price of not decoding 13K JSON blobs per page open. Documented in `data.md`.
- The hidden-Button + `.keyboardShortcut(.cancelAction)` pattern for Esc is reused in three places (popovers, NotFound popover, push-mode WordDetail). Documented in `interaction-model.md` as the canonical recipe for "Esc inside a non-focused container".
- The `user_content` table is intentionally generic on `type`; user notes (planned next) reuse the same schema with `type='note'` — no migration.
