---
id: erudite-8
title: Add pronunciation auto-play and full keyboard shortcut system
status: done
priority: high
estimate: M
---

## Objective

Add two key UX features for efficient study flow: (1) auto-pronunciation when a word card appears, using Youdao API with TTS fallback; (2) full keyboard shortcut system so the entire study session can be operated without mouse.

## Context

- `Erudite/Erudite/Services/PronunciationService.swift` — **Created**: audio playback service
- `Erudite/Erudite/Views/Study/StudyViewModel.swift` — **Modified**: pronunciation integration + skip/goBack + history stack
- `Erudite/Erudite/Views/Study/StudyView.swift` — **Modified**: keyboard handling + auto-focus + shortcut hints UI

## Data Source

Pronunciation audio from [Youdao Dictionary API](https://dict.youdao.com/dictvoice) (same as qwerty-learner):
```
US: https://dict.youdao.com/dictvoice?audio={word}&type=2
UK: https://dict.youdao.com/dictvoice?audio={word}&type=1
Fallback: AVSpeechSynthesizer (macOS built-in TTS, offline)
```

## Tasks

- [x] Create `PronunciationService` — Youdao API + AVSpeechSynthesizer fallback
- [x] Add prefetch logic (cache next word's audio while current card is shown)
- [x] Auto-play pronunciation on card advance
- [x] Add `replayPronunciation()`, `skip()`, `goBack()` to StudyViewModel
- [x] Implement history stack for go-back navigation
- [x] Add `.onKeyPress` handler with full key mapping
- [x] Auto-focus StudyView on appear (no click needed after navigation)
- [x] Re-focus on tab switch back to Study
- [x] Space key: reveal → then rate Good on second press
- [x] Show shortcut hints on UI (monospace key badges)

## Keyboard Shortcuts

| Key | Action | Context |
|-----|--------|---------|
| Space | Reveal answer / Rate Good | Toggle behavior |
| 1 / j | Again | After reveal |
| 2 / k | Hard | After reveal |
| 3 / l | Good | After reveal |
| 4 / ; | Easy | After reveal |
| → / n | Skip (no rating, push to end) | Anytime |
| ← / p | Go back (view only) | Anytime |
| R | Replay pronunciation | Anytime |
| Q / Esc | End session | Anytime |

## Acceptance

- [x] Word is auto-pronounced when card appears
- [x] Keyboard shortcuts work immediately after navigating to Study (no click needed)
- [x] Space toggles: reveal → rate Good
- [x] Skip puts card at end of queue; go-back shows previous card read-only
- [x] Offline fallback works via TTS when network unavailable
- [x] xcodebuild clean build succeeds

## Boundaries

- Always: Prefer Youdao API for quality, fall back to TTS silently
- Always: Show shortcut hints in UI (discoverability)
- Never: Block UI while fetching audio (async + prefetch)
- Never: Allow re-rating on go-back (view only)
