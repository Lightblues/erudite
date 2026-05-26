---
id: erudite-10
title: Dashboard stats view + Today progress display
status: done
priority: medium
estimate: S
---

## Objective

Wire up the existing StatisticsEngine to DashboardView with real data, and add book progress visibility to Today page.

## Changes

| File | Action |
|------|--------|
| `Services/DatabaseService.swift` | **Modified** — added `fetchAllCards()`, `fetchAllReviewLogs()`, `fetchReviewLogs(since:)`, `fetchLearnedCount(inBook:)` |
| `Views/Dashboard/DashboardView.swift` | **Rewritten** — real data binding with Swift Charts (daily activity bar chart, rating donut chart, progress bars) |
| `App/AppState.swift` | **Modified** — `activeBookId` persisted to UserDefaults; added `learnedCount` |
| `Views/Main/TodayView.swift` | **Modified** — book progress bar, stats show Learned/Due/Remaining |

## Features Implemented

### Dashboard
- Overview cards: Mastered / Learning / Retention / Streak (live computed)
- Daily Activity chart: last 14 days bar chart (Swift Charts)
- Rating Distribution: donut chart showing Again/Hard/Good/Easy ratio
- Vocabulary Progress: horizontal bars for Mastered vs Learning vs New

### Today Page
- `activeBookId` persisted to UserDefaults (remembers last selection)
- Progress bar showing learned/total with percentage
- Stats relabeled: Learned / Due / Remaining (more actionable than Total/Due/New)

## Acceptance

- [x] Dashboard shows real computed stats from ReviewCard + ReviewLog data
- [x] Charts render with Swift Charts (bar + donut)
- [x] Book selection persists across app restarts
- [x] Today page shows progress bar when a book is selected
- [x] Build succeeds
