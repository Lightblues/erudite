---
id: erudite-3
title: Build GRE word database from open-source sources
status: done
priority: high
estimate: M
---

## Objective

Build a comprehensive GRE word database (words.json) from multiple open-source vocabulary sources, with frequency tiering and List/Unit organization for structured learning.

## Context

- `scripts/build_worddb.py` — Python build script that merges sources and outputs words.json
- `scripts/pyproject.toml` — uv-managed Python project for build tooling
- `Erudite/Erudite/Resources/Data/words.json` — Generated 5.6MB database (6515 words)
- `Erudite/Erudite/Models/Word.swift` — Updated model (String-based POS/Source for flexibility)
- `Erudite/Erudite/Services/WordLoader.swift` — Loads bundled JSON, seeds SQLite on first launch
- `Erudite/Erudite/App/AppState.swift` — Auto-seeds DB on startup
- `Erudite/Erudite/Views/Library/LibraryView.swift` — Word browser with search + tier filter

## Data Sources

| Source | Role | Words |
|--------|------|-------|
| GRE_3.json (新东方/kajweb) | Primary data (definitions, examples, synonyms, mnemonics) | 6515 |
| 再要你命3000.csv | Frequency signal (tier 1+2 marker) | 3033 |
| MagooshFlashcard.csv | Frequency signal (tier 1 marker) + EN examples | 1008 |

## Tasks

- [x] Research available GRE word lists and data formats
- [x] Analyze field coverage across sources (GRE_2 vs GRE_3 vs CSVs)
- [x] Set up `scripts/` with uv Python environment
- [x] Write `build_worddb.py` — merge, tier, organize pipeline
- [x] Frequency tiering: Core (Magoosh∩再要你命3000), Common (再要你命3000), Advanced (rest)
- [x] List/Unit structure: 66 Lists × 10 Units × 10 words
- [x] Update Swift `Word` model for real-world data flexibility
- [x] Update `WordLoader` to handle new JSON schema
- [x] Wire `AppState` to auto-seed database on launch
- [x] Implement `LibraryView` with search, tier filter, word rows
- [x] Verify xcodebuild succeeds and words.json is bundled

## Results

```
words.json: 6515 words | 5.6 MB
├── Core (tier 1):     524 words  ← Magoosh ∩ 再要你命3000
├── Common (tier 2):  1750 words  ← 再要你命3000
└── Advanced (tier 3): 4241 words ← GRE_3 remaining

Field coverage: phonetic 100% | definitions 100% | synonyms 91% | examples 90% | mnemonics 65%
Structure: 66 Lists × 10 Units × 10 words
```

## Acceptance

- [x] `uv run scripts/build_worddb.py` produces words.json with 6000+ words
- [x] App builds successfully (xcodebuild BUILD SUCCEEDED)
- [x] words.json bundled in app at Contents/Resources/words.json
- [x] Library tab shows word list on launch
