---
id: erudite-4
title: Implement core study session flow with FSRS scheduling
status: done
priority: high
estimate: M
---

## Objective

Implement the complete study session loop: present word cards, allow flip-to-reveal, rate recall, schedule next review via FSRS, and advance to next card. This is the core interaction that makes the app usable.

## Context

- `Erudite/Erudite/Views/Study/StudyView.swift` — Currently placeholder, needs full rewrite
- `Erudite/Erudite/Engine/FSRS/FSRSEngine.swift` — Stub scheduler already returns proper intervals
- `Erudite/Erudite/Services/DatabaseService.swift` — Has `fetchNewCards()`, `fetchDueCards()`, `updateCard()`
- `Erudite/Erudite/Models/ReviewCard.swift` — Card model with state/rating enums ready

## Tasks

- [ ] Create `StudyViewModel` — manages session state (current card, word lookup, flip state, queue)
- [ ] Fetch study queue: new cards (limit 10) + due cards, ordered by priority
- [ ] Implement card face: front shows spelling only, back shows definition + examples + mnemonic
- [ ] Flip interaction: click/spacebar to reveal back
- [ ] Rating buttons: show FSRS intervals, on tap → update card in DB → advance
- [ ] Session progress: show cards remaining, session stats
- [ ] Session complete state: summary of cards studied
- [ ] Add `insertReviewLog()` to DatabaseService for history tracking

## Acceptance

- [ ] Can start a study session and see word cards
- [ ] Tapping/clicking reveals definition, examples, mnemonic
- [ ] Rating a card schedules it and shows next card
- [ ] Session ends gracefully when queue is empty
- [ ] Card state persists — restarting app shows updated due dates

## Boundaries

- Always: Use existing FSRSEngine stub (don't implement full FSRS-5 yet)
- Always: Look up Word from DB by card.wordId to display content
- Never: Modify FSRS algorithm in this issue
- Never: Add network calls or AI features
