---
id: erudite-21
title: "Unified Logging System (os.Logger + File + AI Trace + Debug Panel)"
status: done
priority: medium
estimate: M
---

## Objective

Implement a structured logging system covering all app components. Previously only had scattered `print()` statements and silent `try?` error swallowing. Need observable debugging for AI calls, memory operations, and general app behavior.

## Delivered

### 4-Sink Architecture

```
Log.ai / Log.memory / Log.db / Log.app / Log.ui
    │
    ├→ os.Logger (Console.app, per-category filtering)
    ├→ FileLogger (~/Library/Application Support/Erudite/Logs/, daily rotation, 7-day retention)
    ├→ DebugLog (in-memory 500-entry ring buffer, drives debug panel)
    └→ AITracer (SQLite ai_traces table, per-API-call structured data)
```

### Log Levels
- `debug` — verbose, in-memory only
- `info` — notable events, written to file
- `warning` — potential issues
- `error` — failures, always logged everywhere

### AI Tracing (per API call)
- Model, purpose (chat/extraction/title), input/output tokens
- Cache hit, latency (ms), tool calls list, error message
- Session ID for correlation
- Queryable via SQLite + visible in Debug Panel

### In-App Debug Panel (⌘⇧D)
- Tabs: Logs | AI Traces | Stats
- Logs: real-time, filterable by category and level
- AI Traces: table view (time, model, tokens, latency, tools, errors)
- Stats: today's API calls, total tokens, cache hits

## Files Created (3)
- `App/Log.swift` — Log enum, ELogger, LogLevel, LogEntry, DebugLog, FileLogger
- `Services/AI/AITracer.swift` — AITrace model + SQLite CRUD + todayStats()
- `Views/Debug/DebugPanelView.swift` — 3-tab debug window

## Files Modified (3)
- `DatabaseService.swift` — ai_traces table in setupSchema
- `AgentRuntime.swift` — Log.ai calls on request start/completion/error + AITracer.record()
- `EruditeApp.swift` — Debug window scene with ⌘⇧D shortcut
- `AppState.swift` — AITracer.configure(db:) in init

## Usage Examples

```swift
// In any component:
Log.ai.info("Stream started: model=\(model)")
Log.ai.error("API error", error: error)
Log.memory.debug("Extracted \(count) observations")
Log.db.warning("Slow query: \(ms)ms")

// AI Tracing (automatic in AgentRuntime):
AITracer.shared.record(model: "sonnet", purpose: "chat", inputTokens: 1200, ...)
```
