---
id: erudite-25
title: "Library v2 polish: data versioning, Tier removal, cardState bug, default book"
status: done
priority: med
estimate: M
---

## Objective

Five Library-area improvements driven by reviewing the v2 surfaces in real use:

1. Bundled `words.json` was upgraded v1.0 → v3.0 (ai-enriched mnemonics,
   examples, synonyms for 99% of words), but only fresh installs got the
   new fields — existing DBs kept v1.0 sparse data forever.
2. The Library "Tier" picker was UX clutter (83% of words landed in the
   "advanced" bucket, no authoritative GRE provenance).
3. Library's State filter said "Review" but every row's badge showed
   "New" — a silent type-coercion bug in the GRDB row reader.
4. Library defaulted to "All Books" instead of the user's current book,
   so you'd open Library mid-study and see 13K unrelated words.
5. SQL needed proper indexes for the new sort modes; A→Z over 13K rows
   was full-scan + sort.

## Context

Followup to erudite-24 (Word Management overhaul). After daily use, the
above five issues were the highest-friction remaining items in the
Library/Today/Plan flow. The v3.0 enrichment problem is the most
impactful — without the upgrade path, all the AI work shipped in
words.json was effectively unreachable.

## Deliverables

### A. Data versioning + upgrade path
- New `meta(key, value)` table tracks the last-applied bundled version.
- `WordLoader.seedDatabaseIfNeeded()` now picks one of three paths based
  on the comparison `meta.wordsVersion` vs `words.json:version`:
  - **Fresh install:** insert all words + create FSRS cards + seed books.
  - **Upgrade:** UPDATE existing word.data in place (preserves FSRS
    progress); INSERT new words + cards.
  - **Up to date:** no work.
- Critical: uses UPDATE, not `INSERT OR REPLACE`. REPLACE is
  DELETE-then-INSERT under the hood, and `reviewCard.wordId` has
  `ON DELETE CASCADE` — REPLACE would have wiped every user's review
  history mid-launch.

### B. Tier removal
- Removed `Tier` picker from Library header.
- Removed `WordSort.frequency`; default sort is now `WordSort.bookOrder`
  (uses `wordListEntry.sortOrder` when a book is selected; silently
  falls back to A→Z otherwise).
- Removed C/M/A tier circle from `WordSummaryRow`.
- Removed `tier:` parameter from `fetchWordSummaries` /
  `fetchWordSummaryCount`.
- Removed tier badge from `WordDetailView` and `StudyView` flashcard front.
- Kept `Word.frequency` on the model — so we can reintroduce a real
  importance signal later (corpus rank, per-book weights) without a
  migration.

### C. cardState typed-annotation bug
- `Row.subscript` with `as? Int` silently fails for `Int64` columns.
- Fixed `rowToSummary` to use `let stateRaw: Int? = row["cardState"]`
  (and same for `frequency`, `hasMnemonic`).
- Same gotcha noted in lessons.md and data.md so we don't trip again.

### D. Library default book + two-way sync with AppState
- `LibraryView` now seeds `selectedBookId` from `AppState.activeBookId`
  on first appear.
- Picker changes are pushed back to `AppState.selectBook(_:)` so
  Today/Plan/Library always agree on the current book.
- Pulls AppState changes (e.g. user changed book on Today) into the
  picker so it reflects the latest state.

### E. SQL indexes for new sort modes
- `idx_word_spelling` on `word(spelling COLLATE NOCASE)` — A→Z is
  index-only.
- `idx_wle_list_order` on `wordListEntry(listId, sortOrder)` — book-order
  pagination is a 2-step index lookup, not a sort.
- Verified via `EXPLAIN QUERY PLAN`.

### F. DataDiagnosticsView (Debug Panel ⌘⇧D → Data tab)
- Read-only diff between bundled words.json and live DB:
  - Bundle vs DB version + word count delta.
  - Word-set delta (bundle-only / DB-only — DB-only words come from
    `WordLookupService` cache hits during reading).
  - Per-field upgrade counts (how many words gain a chinese def,
    mnemonic, example, etc. on the next upgrade).
- Pure analysis; no writes.

## Files

### Created
- `Erudite/Erudite/Views/Debug/DataDiagnosticsView.swift` — read-only
  diff view + report builder

### Modified
- `Erudite/Erudite/Models/WordSummary.swift` — `WordSort.bookOrder`,
  removed `.frequency`
- `Erudite/Erudite/Services/DatabaseService.swift` — `meta` table,
  `metaValue`/`setMetaValue`, `upsertWordData`, dropped `tier` arg from
  query builder, fixed `rowToSummary` typed annotations, added
  `idx_word_spelling` + `idx_wle_list_order`
- `Erudite/Erudite/Services/WordLoader.swift` — version-driven
  three-path seed/upgrade flow, `loadBundledDatabase()` exposed for
  diagnostics
- `Erudite/Erudite/Views/Components/WordSummaryRow.swift` — dropped
  tier badge
- `Erudite/Erudite/Views/Library/LibraryView.swift` — removed Tier
  picker, default-book wiring + two-way sync with AppState
- `Erudite/Erudite/Views/Library/WordDetailView.swift` — dropped tier
  badge + helpers
- `Erudite/Erudite/Views/Study/StudyView.swift` — dropped tier badge
- `Erudite/Erudite/Views/Debug/DebugPanelView.swift` — added Data tab

### Specs / docs
- `.ea/spec/features.md` — Library section: dropped Tier, documented
  Book Order as default sort, two-way book sync
- `.ea/spec/data.md` — Tier note on `FrequencyTier`, "Data Versioning
  and Upgrade" section, indexes section, GRDB Int64 typed-subscript
  warning, dropped `tier` from method signature
- `.ea/spec/lessons.md` — five new lessons (cardState bug,
  debugserver-blocks-LaunchServices, INSERT OR REPLACE wipes FSRS
  history, Tier filter without provenance, version-from-day-one)

## Verification

1. Killed any running Erudite + debugserver.
2. Cleared `meta` rows so the upgrade path would fire.
3. Pre-launch state recorded: `belligerent` had 0 mnemonics; reviewCard
   distribution `0=13001, 1=12, 2=98, 3=1`.
4. Launched the rebuilt app; waited for `seedDatabaseIfNeeded`.
5. Post-launch:
   - `meta.wordsVersion = 3.0` ✓
   - `belligerent` now has the v3.0 ai-enriched mnemonic
     ("belli(战争) + ger(带来) + ent(形容词后缀) → 带来战争的 → 好战的") ✓
   - reviewCard distribution **identical** to pre-launch — FSRS
     progress fully preserved across the upgrade ✓
   - Word count preserved (13141, including 29 cached lookups not in
     the bundle) ✓
6. `EXPLAIN QUERY PLAN` confirmed both new indexes are used.
7. Build clean: `xcodebuild build` returns BUILD SUCCEEDED.

## Acceptance criteria

- [x] V1.0 → V3.0 word.data upgraded for existing installs without
      losing reviewCard / reviewLog / user_content
- [x] meta table created and `wordsVersion` stamped
- [x] Library "Tier" filter removed; bookOrder is default sort
- [x] cardState shows correct state in Library row badges
- [x] Library defaults to active book on first appear
- [x] Two-way sync between Library Book picker and AppState.activeBookId
- [x] A→Z and book-order sorts use indexes (no full-scan + sort)
- [x] Debug Panel → Data tab shows diff report
- [x] Build clean and runtime verified end-to-end
