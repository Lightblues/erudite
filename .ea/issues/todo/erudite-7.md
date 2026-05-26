---
id: erudite-7
title: Implement word data merge/enrich infrastructure for schema evolution
status: todo
priority: medium
estimate: M
---

## Objective

Build infrastructure to evolve word data over time: allow AI-enriched fields (roots, mnemonics, sentiment) to be written back into the word BLOB, support merge-on-update when words.json is bumped, and enable periodic export of enriched data back to the build pipeline.

## Context

- `Erudite/Erudite/Services/DatabaseService.swift` — needs `updateWordData()` method
- `Erudite/Erudite/Services/WordLoader.swift` — seed logic needs merge (not overwrite)
- `scripts/build_worddb.py` — needs `--merge` flag to ingest enriched exports
- `Erudite/Erudite/Resources/Data/words.json` — versioned baseline

## Tasks

- [ ] Add `DatabaseService.updateWordData(_ word: Word)` — update BLOB in place
- [ ] Change `WordLoader.seedDatabaseIfNeeded()` to version-aware merge:
  - Compare `words.json` version vs stored DB version
  - New words → insert; existing words → merge (preserve user/AI enriched fields)
- [ ] Define merge priority: user-added > AI-generated > prebuilt baseline
- [ ] Create `scripts/export_enriched.py` — export DB words back to JSON
- [ ] Add `--merge enriched.json` option to `build_worddb.py`
- [ ] Store DB schema version in a metadata table

## Acceptance

- [ ] AI-enriched roots/mnemonics persist in word.data BLOB (not only aiCache)
- [ ] App update with new words.json merges without losing user data
- [ ] `export_enriched.py` produces valid JSON that `build_worddb.py` can reingest

## Boundaries

- Always: Preserve user-generated content over prebuilt data
- Always: Version the words.json and store version in DB for comparison
- Never: Silently overwrite user/AI enriched fields on app update
- Never: Require network for merge logic (offline-first)
