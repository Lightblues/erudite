---
id: erudite-14
title: Speed review mode (rapid yes/no recognition)
status: todo
priority: low
estimate: S
---

## Objective

Fast-paced review mode: show word → "Know it?" (yes/no). Optimized for high volume review of learned words, testing passive recognition speed.

## Context

- Useful for reinforcing large batches (100+ cards in 5 min)
- Binary signal: Know → skip (implicit Good), Don't Know → mark for re-study (Again)
- Similar to Anki's "overview" or quiz apps' speed rounds
- Should show word briefly, auto-advance on "Know"

## Tasks

- [ ] Speed review UI: word only, large font, two buttons (Know / Don't Know)
- [ ] Auto-advance after "Know" (0.5s delay for visual feedback)
- [ ] "Don't Know" briefly flashes definition, then advances
- [ ] Timer display (session elapsed + cards/minute rate)
- [ ] End-of-session summary: X cards reviewed in Y minutes, Z marked for re-study
- [ ] Map to FSRS: Know → Good, Don't Know → Again
- [ ] Keyboard: → or Space = Know, ← or X = Don't Know

## Acceptance

- [ ] Can review 50+ cards in under 3 minutes
- [ ] "Don't Know" cards get scheduled for near-term review
- [ ] Session summary shows speed metrics
- [ ] Keyboard-only operation (no mouse needed)
- [ ] Build succeeds
