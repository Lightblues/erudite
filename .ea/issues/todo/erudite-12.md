---
id: erudite-12
title: Quiz mode (multiple choice + fill-in-the-blank)
status: todo
priority: medium
estimate: M
---

## Objective

Add quiz review modes beyond flashcard: multiple-choice (choose correct definition) and fill-in-the-blank (type the word from definition).

## Context

- Current: only flashcard mode (show word → reveal definition → self-rate)
- Quiz mode tests active recall more rigorously
- Distractor selection matters: should use semantically similar words (same frequency tier, same book) to be challenging but fair

## Tasks

- [ ] Define `ReviewMode` enum: `.flashcard`, `.multipleChoice`, `.fillBlank`
- [ ] Multiple choice: show definition → pick correct word from 4 options
- [ ] Fill-in-the-blank: show definition + first letter hint → type word
- [ ] Distractor generation: pick 3 wrong answers from same book/tier
- [ ] Map quiz results to FSRS ratings (correct→Good, wrong→Again, slow-correct→Hard)
- [ ] Add mode selector to study launch flow
- [ ] Keyboard support: 1/2/3/4 for MC, Enter to submit fill-blank

## Acceptance

- [ ] Multiple choice shows 4 options with correct answer randomly positioned
- [ ] Fill-in-the-blank validates spelling (case-insensitive)
- [ ] Wrong answers trigger FSRS "Again" rating automatically
- [ ] Distractors are plausible (not random unrelated words)
- [ ] Build succeeds
