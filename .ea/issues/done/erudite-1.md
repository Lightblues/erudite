---
id: erudite-1
title: Initialize Xcode project skeleton with core structure and dependencies
status: done
priority: high
estimate: M
---

## Objective

Set up the Erudite macOS app project from scratch — Xcode project, directory structure,
SPM dependencies, core data models, and a minimal running app with navigation shell.
This provides the foundation for all subsequent feature work.

## Context

- `.ea/spec/architecture.md` — defines target project structure, dependencies, patterns
- `.ea/spec/data.md` — defines Swift data models and SQLite schema
- No source code exists yet; only spec files and git repo

## Tasks

- [x] Create Swift Package project (macOS 14+, Swift 5.9+)
- [x] Set up directory structure: App/, Models/, Engine/, Services/, ViewModels/, Views/, Resources/
- [x] Add SPM dependency: GRDB.swift
- [x] Implement core data models as defined in data.md:
      Word, Definition, MorphemeBreakdown, ReviewCard, ReviewLog, StudySession, WordList
- [x] Implement FSRS enums and card state types (CardState, Rating, Sentiment, FrequencyTier)
- [x] Create FSRSEngine interface + stub implementation (returns fixed intervals)
- [x] Create DatabaseService with GRDB schema setup (all tables from data.md)
- [x] Create AIProvider protocol + AIService stub (no API calls yet, just interface)
- [x] Create app entry point (EruditeApp.swift) with NavigationSplitView shell
- [x] Create placeholder views: TodayView, StudyView, LibraryView, DashboardView
- [x] Add a bundled seed words.json with 8 sample words for development testing
- [x] Verify app compiles (`swift build` succeeds with zero errors)

## Acceptance

- [x] `swift build` succeeds with zero errors
- [x] App has sidebar with navigation items (Today, Learn, Library, Stats)
- [x] Clicking sidebar items switches the detail view (placeholder content)
- [x] GRDB database schema defined (tables created on first launch)
- [x] All model types conform to Codable — round-trip verified by 4 passing tests
- [x] Sample words.json (8 words) loads and parses into [Word] array

## Boundaries

- Always: Follow architecture.md structure exactly (MVVM + Repository)
- Always: Use @Observable (not ObservableObject) for ViewModels
- Always: Keep views as thin shells — no business logic in Views
- Never: Implement actual FSRS scheduling logic (that's a separate issue)
- Never: Make real AI API calls (stub only)
- Never: Add UI polish or styling (functional skeleton only)
