---
id: erudite-9
title: Multi-wordbook architecture with shared vocabulary pool
status: done
priority: high
estimate: L
---

## Objective

Support multiple word books (GRE, TOEFL, SAT, 词以类记) with independent study ordering, while sharing word knowledge and FSRS state globally across books.

## Context

Previously Erudite had a single flat 6515-word GRE database. Users need to study different exams or different orderings of the same exam (e.g. 频率序 vs 语义簇序). The DB schema already had unused `wordList`/`wordListEntry` tables — this issue wires them up end-to-end.

## Design Decisions

- **Word is global**: same spelling → one `word` row, one `ReviewCard`. Learning "aberrant" in GRE 3000 means it's learned in 词以类记 too.
- **Book provides ordering**: `wordListEntry.sortOrder` determines which word comes next within each book.
- **No `listIndex`/`unitIndex` on Word**: removed legacy per-word positioning; ordering is now per-book via join table.
- **No `wordsPerUnit`**: not a data property — purely UX, can be computed at display time if needed.
- **Word merging strategy**: existing rich data (GRE_3 enriched) is never overwritten; new books reference existing words or create minimal stubs.

## Files Changed

| File | Action |
|------|--------|
| `scripts/build_multibook.py` | **Created** — import 6 word books from qwerty-learner, merge into shared word pool |
| `Erudite/.../Resources/Data/words.json` | **Regenerated** — 6515→13112 words, alphabetically sorted, indent=2 |
| `Erudite/.../Resources/Data/wordbooks.json` | **Created** — 6-book manifest with ordered word IDs |
| `Models/Word.swift` | **Modified** — removed `listIndex`/`unitIndex` |
| `Models/WordList.swift` | **Modified** — renamed to `WordBook`, added `exam`/`structure`/`source` |
| `Services/DatabaseService.swift` | **Modified** — added `fetchWords(inBook:)`, `fetchDueCards(inBook:)`, `fetchNewCards(inBook:)`, `insertWordBook()`, `insertWordBookEntries()`, `fetchWordBooks()` |
| `Services/WordLoader.swift` | **Modified** — `seedWordBooks()` + upgrade path for existing installs |
| `App/AppState.swift` | **Modified** — `activeBookId`, `wordBooks[]`, `selectBook()` |
| `Views/Study/StudyViewModel.swift` | **Modified** — `start(database:mode:bookId:)` |
| `Views/Study/StudyView.swift` | **Modified** — passes `activeBookId` |
| `Views/Main/TodayView.swift` | **Modified** — word book Picker, scoped stats |
| `Views/Library/LibraryView.swift` | **Modified** — filter by book |
| `Views/Library/WordDetailView.swift` | **Modified** — removed listIndex display |

## Word Books

| ID | Name | Exam | Words | Structure |
|----|------|------|-------|-----------|
| `gre-3000` | GRE 再要你命3000 | GRE | 3036 | sequential |
| `gre-ciyileiji` | GRE 词以类记 | GRE | 8384 | thematic |
| `gre-equivalent` | GRE 等价词 | GRE | 827 | sequential |
| `toefl-core` | TOEFL 核心 | TOEFL | 4264 | sequential |
| `toefl-ciyileiji` | TOEFL 词以类记 | TOEFL | 3669 | thematic |
| `sat-core` | SAT 核心 | SAT | 4463 | sequential |

## Tasks

- [x] Copy qwerty-learner word book JSONs to `data/raw/`
- [x] Create `build_multibook.py` — parse, merge, deduplicate, output
- [x] Generate `words.json` (13112 words, sorted, indent=2) and `wordbooks.json`
- [x] Update `Word` model — remove `listIndex`/`unitIndex`
- [x] Create `WordBook` model with exam/structure metadata
- [x] Add DB queries filtered by book (`inBook:` parameter)
- [x] Add `insertWordBook()` and `insertWordBookEntries()` to DatabaseService
- [x] Update `WordLoader` seeding — word books + upgrade path
- [x] Add `activeBookId` to AppState with scoped stats
- [x] Pass bookId through StudyViewModel → DB queries
- [x] Add book Picker to TodayView
- [x] Add book filter to LibraryView
- [x] Remove all `listIndex`/`unitIndex` references from Views
- [x] Verify `xcodebuild build` succeeds

## Acceptance

- [x] `uv run scripts/build_multibook.py` is idempotent (0 new words on re-run)
- [x] `words.json` is alphabetically sorted (clean git diffs)
- [x] Build succeeds with no errors
- [x] TodayView shows book Picker with 6 books + "All Books" option
- [x] Selecting a book scopes Due/New counts
- [x] Study session fetches cards only from selected book
- [x] Review Due pulls from all books (global FSRS state)
- [x] Library can filter words by book

## Boundaries

- Always: Existing rich word data is never overwritten by new book imports
- Always: A word learned in any book is learned globally (one ReviewCard per word)
- Never: Store UX preferences (wordsPerUnit, chapter size) in data layer
- Future: AI context isolation per study plan (shared word knowledge, isolated teaching strategy)
