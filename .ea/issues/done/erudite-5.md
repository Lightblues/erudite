---
id: erudite-5
title: Wire navigation and TodayView live stats
status: done
priority: high
estimate: S
---

## Objective

Connect TodayView action buttons to actual navigation targets and display real-time stats (due cards, new cards) from the database. Without this, users can't start a study session from the home screen.

## Context

- `Erudite/Erudite/Views/Main/TodayView.swift` — Buttons have empty actions, stats show "—"
- `Erudite/Erudite/Views/Main/ContentView.swift` — NavigationSplitView with tab selection
- `Erudite/Erudite/App/AppState.swift` — Holds `selectedTab`, `databaseService`
- `Erudite/Erudite/Services/DatabaseService.swift` — Has `fetchDueCards()`, `fetchNewCards()`

## Tasks

- [ ] Add `dueCount` and `newCount` properties to AppState (computed from DB)
- [ ] TodayView: display real due/new counts in StatBadges
- [ ] "Start Learning" button → switch to .study tab (new + due cards)
- [ ] "Quick Review" button → switch to .study tab (due cards only)
- [ ] Refresh stats when returning to Today tab

## Acceptance

- [ ] TodayView shows actual number of due and new cards
- [ ] "Start Learning" navigates to study session
- [ ] Stats update after completing a study session

## Boundaries

- Always: Use existing AppState.selectedTab for navigation
- Never: Add new navigation patterns (sheets, popovers) — keep it simple
- Never: Block UI while querying DB (use async)
