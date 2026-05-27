# Erudite — GRE Vocabulary Learning App

AI-native macOS vocabulary app for GRE/TOEFL/SAT preparation. Built with Swift + SwiftUI.

## Spec Files

| File | Description |
|------|-------------|
| [product.md](product.md) | Product vision, positioning, and feature overview |
| [features.md](features.md) | Detailed feature design and interaction modes |
| [ai-system.md](ai-system.md) | AI Teacher architecture and integration design |
| [data.md](data.md) | Word database schema, sources, and pipeline |
| [architecture.md](architecture.md) | Technical architecture, project structure, dependencies |
| [development.md](development.md) | Development guide, tooling, coding conventions |

## Current Implementation Status

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-wordbook (6 books, 13k words) | ✅ Done | GRE/TOEFL/SAT, shared word pool |
| Flashcard mode (FSRS) | ✅ Done | Stub FSRS (fixed intervals), full UI with header/settings/word list |
| Typing Practice (qwerty-learner) | ✅ Done | Separate tab, full feature set |
| Interactive Dictionary | ✅ Done | Click any English word → popover or Eudic fallback |
| Dashboard / Stats | ✅ Done | Swift Charts, live stats |
| KeyCaptureView (focus system) | ✅ Done | NSViewRepresentable, replaces @FocusState hacks |
| FSRS-5 real algorithm | 📋 Todo | Issue #11 |
| Quiz / SE pairing | 📋 Todo | Issues #12, #13 |
| Speed Review | 📋 Todo | Issue #14 |
| AI Teacher | 📋 Todo | — |
