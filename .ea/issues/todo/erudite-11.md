---
id: erudite-11
title: Implement FSRS-5 scheduling algorithm
status: todo
priority: high
estimate: M
---

## Objective

Replace the stub FSRSEngine (fixed 1/3/7/14 day intervals) with the real FSRS-5 algorithm so that spaced repetition actually adapts to user performance.

## Context

- Current stub: `Engine/FSRS/FSRSEngine.swift` returns hardcoded intervals regardless of rating history
- FSRS-5 paper: https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
- Reference impl: https://github.com/open-spaced-repetition/swift-fsrs (MIT license)
- Our ReviewCard already stores all FSRS state (stability, difficulty, reps, lapses, elapsedDays, scheduledDays)

## Tasks

- [ ] Implement FSRS-5 parameter set (w[0]..w[18] default weights)
- [ ] `schedule(card:, rating:)` → returns updated card with new stability/difficulty/interval
- [ ] Handle state transitions: New→Learning, Learning→Review, Review→Review/Relearning
- [ ] Compute retrievability (memory decay curve) for retention display
- [ ] `nextIntervals(card:)` → preview all 4 intervals for UI (Again=?d, Hard=?d, Good=?d, Easy=?d)
- [ ] Unit tests for scheduling correctness

## Acceptance

- [ ] After rating "Good" on a new card, next interval > 1 day
- [ ] Stability increases on successful recall, decreases on lapse
- [ ] Study UI shows realistic interval previews (not fixed 1/3/7/14)
- [ ] Rating "Again" resets to short interval (relearning)
- [ ] Build succeeds + unit tests pass
