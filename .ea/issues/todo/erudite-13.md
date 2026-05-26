---
id: erudite-13
title: Sentence Equivalence (SE) pairing mode
status: todo
priority: medium
estimate: M
---

## Objective

GRE-specific review mode: given a word, identify its synonym pair from options. Trains the "SE pairing" skill critical for GRE Verbal.

## Context

- GRE SE questions: pick 2 words that create equivalent sentences
- We have `gre-equivalent.json` (827 entries) with synonym clusters
- Also have `synonymGroups` in Word model for rich words
- This mode is unique to GRE prep — a differentiator

## Tasks

- [ ] Parse SE pairing data (word → list of equivalents)
- [ ] SE mode UI: show target word → select which 2 of 6 options are its synonyms
- [ ] Score: both correct = Good, one correct = Hard, neither = Again
- [ ] Use synonym data from Word model as additional source
- [ ] Prioritize SE practice for words with known synonym groups
- [ ] Track SE-specific accuracy in review logs (tag or mode field)

## Acceptance

- [ ] SE mode presents word with 6 options (2 correct synonyms + 4 distractors)
- [ ] Distractors are plausible (similar frequency/domain)
- [ ] Correct pair highlighted after answer
- [ ] Results feed into FSRS scheduling
- [ ] Build succeeds
