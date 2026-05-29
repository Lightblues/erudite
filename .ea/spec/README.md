# Erudite — GRE Vocabulary Learning App

AI-native macOS vocabulary app for GRE/TOEFL/SAT preparation. Built with Swift + SwiftUI.

## Spec Files

| File | Description |
|------|-------------|
| [product.md](product.md) | Product vision, positioning, and feature overview |
| [features.md](features.md) | Detailed feature design and interaction modes |
| [interaction-model.md](interaction-model.md) | Focus & keyboard model: main/chat zones, click routing, shortcuts |
| [ai-system.md](ai-system.md) | AI Teacher architecture and integration design |
| [ai-companion.md](ai-companion.md) | AI Companion: agent runtime, memory, tools, proactive engine |
| [data.md](data.md) | Word database schema, sources, and pipeline |
| [architecture.md](architecture.md) | Technical architecture, project structure, dependencies |
| [development.md](development.md) | Development guide, tooling, coding conventions |
| [lessons.md](lessons.md) | Time-ordered dev log of pitfalls, root causes, and takeaways |

## Current Implementation Status

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-wordbook (6 books, 13k words) | ✅ Done | GRE/TOEFL/SAT, shared word pool |
| Flashcard mode (FSRS) | ✅ Done | Stub FSRS, full UI with header/settings/word list/session summary |
| Typing Practice (qwerty-learner) | ✅ Done | Separate tab, full feature set |
| Interactive Dictionary | ✅ Done | Click words → popover (local) or API (MW/FreeDict) with cache |
| Focus & keyboard model | ✅ Done | Issue #23: `focusZone` source-of-truth + window click routing; KeyCaptureView (NSView) for study, TextEditor for chat (see interaction-model.md) |
| Data Pipeline (ECDICT + AI) | ✅ Done | 13K words enriched: phonetics, freq, tags, mnemonics, examples |
| Config Management | ✅ Done | Config.json (git-ignored) + AppConfig.swift |
| Dashboard / Stats | ✅ Done | Swift Charts, live stats |
| AI Companion P0 (Agent + Chat) | ✅ Done | Issue #19: SSE client, agent loop, 4 tools, side panel |
| AI Companion P1 (Memory) | ✅ Done | Issue #20: sessions, observations, memory tools, model tiering |
| Logging System | ✅ Done | Issue #21: os.Logger + file + AI trace + debug panel (⌘⇧D) |
| Chat UX & Traceability | ✅ Done | Issue #22: resizable panel, tool-call inspection, token/latency/request-id, multiline input |
| FSRS-5 real algorithm | 📋 Todo | Issue #11 |
| Quiz / SE pairing | 📋 Todo | Issues #12, #13 |
| Speed Review | 📋 Todo | Issue #14 |
| AI Companion P2 (Proactive Tips) | 📋 Todo | Event-driven tips during study |
