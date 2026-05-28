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
| Flashcard mode (FSRS) | ✅ Done | Stub FSRS, full UI with header/settings/word list/session summary |
| Typing Practice (qwerty-learner) | ✅ Done | Separate tab, full feature set |
| Interactive Dictionary | ✅ Done | Click words → popover (local) or API (MW/FreeDict) with cache |
| KeyCaptureView (focus system) | ✅ Done | NSViewRepresentable, replaces @FocusState hacks |
| Data Pipeline (ECDICT + AI) | ✅ Done | 13K words enriched: phonetics, freq, tags, mnemonics, examples |
| Config Management | ✅ Done | Config.json (git-ignored) + AppConfig.swift |
| Dashboard / Stats | ✅ Done | Swift Charts, live stats |
| FSRS-5 real algorithm | 📋 Todo | Issue #11 |
| Quiz / SE pairing | 📋 Todo | Issues #12, #13 |
| Speed Review | 📋 Todo | Issue #14 |
| AI Teacher | 📋 Todo | — |
