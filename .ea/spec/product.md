# Product Spec

## Overview

**Name:** Erudite  
**Platform:** macOS (native)  
**Tech Stack:** Swift + SwiftUI  
**Target User:** GRE test taker (self-use, personal tool)  
**Minimum macOS:** 14 (Sonoma)+

## Positioning

An AI-native vocabulary learning app that goes beyond flashcards. The AI is not a feature — it is the fabric of the entire experience.

### Core Principles

1. **AI as Foundation** — Every interaction is potentially AI-enhanced; the app continuously adapts to the user
2. **Scientifically Grounded** — FSRS algorithm for scheduling, active recall as primary method
3. **GRE-Specific** — Designed for GRE Verbal (TC/SE), not generic vocabulary
4. **Progressively Evolving** — The app summarizes daily progress and generates personalized study plans

## GRE Context

### Exam Structure (Shorter GRE, post-2023)

- Verbal Reasoning: 27 questions, 41 minutes (2 sections)
- Quantitative Reasoning: 27 questions, 47 minutes (2 sections)  
- Analytical Writing: 1 Issue essay, 30 minutes

### Verbal Question Types (vocabulary-relevant)

- **Text Completion (TC):** 1-3 blanks, tests precise word meaning
- **Sentence Equivalence (SE):** Select 2 synonyms that make sentence equivalent
- **Reading Comprehension (RC):** Indirectly tests vocabulary

### Vocabulary Requirements

- Core mastery: ~1000-1500 high-frequency words covers most TC/SE
- Deep prep: expand to 3000+
- Key dimensions: precise meaning, sentiment (positive/negative/neutral), synonym groups, word roots

## Key Differentiators vs Existing Apps

| Aspect | Traditional Apps (Anki, GRE3000) | Erudite |
|--------|----------------------------------|---------|
| Scheduling | Fixed or basic SRS | FSRS (state-of-the-art) |
| Content | Static definitions | AI-generated personalized mnemonics |
| Learning path | Fixed word list order | AI adapts daily plan to weaknesses |
| Assistance | User must self-diagnose | Context-aware AI teacher always present |
| Review modes | Single mode | Multiple modes matched to learning stage |
| Word relationships | Flat list | Semantic clusters, root families, confusion pairs |

## Feature Modules (High Level)

```
┌─────────────────────────────────────────────────────┐
│                     Erudite                           │
├──────────┬──────────┬───────────┬───────────────────┤
│  📚 Learn │  📊 Stats │  🧩 Roots  │  🤖 AI Teacher   │
│  (FSRS)  │ Dashboard│  Explorer │  (always present) │
├──────────┴──────────┴───────────┴───────────────────┤
│  📇 Review: Flashcard | Quiz | Speed Review          │
└─────────────────────────────────────────────────────┘
```

## Learning Stage Model

```
[初见] ──→ [初记] ──→ [巩固] ──→ [熟练] ──→ [应用]
  │          │          │          │          │
 学习卡片   抽认卡     做题巩固    极速刷词    真题练习
 + AI讲解   + 词根联想  + SE/TC    + 听力复习   (future)
```

## Roadmap (Phases)

### Phase 1: Core Learning Loop
- FSRS engine + card study view
- Basic word database (1500+ core words)
- 4-rating review flow
- Local SQLite storage

### Phase 2: Review Modes + Stats
- Flashcard review mode
- Quiz mode (word→def, def→word, SE pairing)
- Dashboard with retention charts and heatmap
- Speed review mode

### Phase 3: AI Integration
- AI Teacher bar (context-aware)
- Daily briefing and session summaries
- Personalized mnemonic generation
- Weakness detection and adaptive planning

### Phase 4: Polish + Extended Features
- Word root explorer visualization
- Import/export (Anki format, CSV)
- Exam countdown mode
- (Future) GRE practice question integration
