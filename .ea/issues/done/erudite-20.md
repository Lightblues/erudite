---
id: erudite-20
title: "AI Companion P1: Memory System (Session Persistence + Observations)"
status: done
priority: high
estimate: L
---

## Objective

Add long-term memory to the AI companion: conversation persistence across app restarts, multi-session management, and observation extraction for cross-session learning.

## Delivered

### Session Persistence
- Messages saved to SQLite after each AI turn
- App resumes last session on launch (messages restored into AgentRuntime)
- Full ContentBlock JSON preserved for API replay (tool_use/tool_result)

### Multi-Session Management
- Create new sessions, switch between existing ones
- Session list popover with title, date, message count
- Auto-title generation (fast model, after first exchange)
- Delete sessions (cascade deletes messages)

### Observation Extraction (Semantic Memory)
- Watermark-based extraction (every 5 user-visible turns)
- Flush on app going to background
- BackgroundAI uses fast model (non-streaming collection)
- Deduplication: same-type similar content → bump confidence
- Observations injected into system prompt automatically

### Memory Tools (Agent can query its own memory)
- `recall_observations`: search past observations by keyword/type
- `search_past_conversations`: search session titles/summaries

### Model Tiering
- `aiFastModel` config field for background tasks (extraction, title gen)
- Fallback: aiFastModel → aiModel → haiku (graceful degradation)

## Files Created (6)
- `Services/AI/SessionManager.swift` — Session + message CRUD, load/save/switch
- `Services/AI/MemoryStore.swift` — Observations CRUD, extraction trigger, prompt injection
- `Services/AI/BackgroundAI.swift` — Fast-model calls (streaming collected)
- `Services/AI/Tools/RecallObservationsTool.swift` — Query observations tool
- `Services/AI/Tools/SearchConversationsTool.swift` — Search sessions tool
- `Views/AI/SessionListView.swift` — Session list popover UI

## Files Modified (6)
- `DatabaseService.swift` — +4 tables: ai_sessions, ai_messages, ai_observations, ai_traces
- `AgentRuntime.swift` — loadMessages(), onTurnComplete callback, ChatMessage restore init
- `SystemPrompt.swift` — Memory section injection + memory tool instructions
- `Tools/AITool.swift` — Register 2 new memory tools
- `AppConfig.swift` — aiFastModel + resolvedFastModel (fallback chain)
- `Views/AI/AIChatPanel.swift` — Session header (title + new/list buttons)
- `App/AppState.swift` — sessionManager, memoryStore, backgroundAI wiring + flushMemory()
- `App/EruditeApp.swift` — App lifecycle hook (willResignActive → flush)

## Key Design Decisions
- Observations are global (cross-session), messages are per-session
- BackgroundAI uses streaming internally (proxy compatibility) but collects full response
- onTurnComplete callback decouples AgentRuntime from persistence logic
- AISession title auto-generated after first exchange, editable later
