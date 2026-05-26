---
id: erudite-6
title: Add word detail view in Library
status: done
priority: medium
estimate: S
---

## Objective

Allow tapping a word in LibraryView to see its full details: all definitions, examples, synonyms, mnemonic, and metadata. Essential for browsing and self-study outside of FSRS sessions.

## Context

- `Erudite/Erudite/Views/Library/LibraryView.swift` — Word rows exist, need navigation to detail
- `Erudite/Erudite/Models/Word.swift` — Full model with definitions, examples, synonymGroups, mnemonics

## Tasks

- [ ] Create `WordDetailView.swift` in Views/Library/
- [ ] Display: spelling, phonetic, all definitions (POS + EN + ZH)
- [ ] Display: example sentences with source labels
- [ ] Display: synonym groups as chips/tags
- [ ] Display: mnemonic(s) with visual highlight
- [ ] Display: metadata (frequency tier, list/unit position)
- [ ] Wire NavigationLink from WordRow in LibraryView

## Acceptance

- [ ] Tapping a word in Library navigates to detail view
- [ ] All word fields are visible and well-formatted
- [ ] Back navigation returns to list with scroll position preserved

## Boundaries

- Always: Read-only view (no editing word data in this issue)
- Never: Add audio playback or TTS (future issue)
