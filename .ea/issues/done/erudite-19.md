---
id: erudite-19
title: "AI Companion P0: Agent Runtime + Chat Panel"
status: done
priority: high
estimate: L
---

## Objective

Implement the foundational AI companion: a tool-augmented agent with a fixed right-side chat panel. The AI can query the user's actual learning state via tools and provide personalized responses with streaming output.

## Delivered

### Architecture
- Self-implemented Anthropic Messages API client (no SDK dependency)
- SSE streaming parser (handles partial chunks, comments, multi-line data)
- Agent loop: messages → LLM → tool_use → execute → loop back
- 4 read-only tools querying real FSRS/DB state
- Fixed right-side panel UI with streaming text display

### Files Created (17)
- `Services/AI/AnthropicTypes.swift` — Codable types, JSONValue, StreamEvent
- `Services/AI/SSEParser.swift` — SSE line protocol parser
- `Services/AI/AnthropicClient.swift` — HTTP client, Bearer/x-api-key dual auth
- `Services/AI/AgentRuntime.swift` — Agent loop, ChatMessage, UI throttling (50ms)
- `Services/AI/SystemPrompt.swift` — Persona + context builder
- `Services/AI/Tools/AITool.swift` — Protocol + ToolRegistry
- `Services/AI/Tools/Get{UserStats,WordHistory,WeakWords,CurrentSession}Tool.swift`
- `Services/AI/Tools/DatabaseService+AI.swift` — DB query extensions
- `Views/AI/AIChatPanel.swift` — Panel container with suggestions
- `Views/AI/Chat{Message,Input}View.swift` — Message bubble + input
- `Views/AI/StreamingTextView.swift` — Streaming text + cursor
- `Views/AI/ThinkingIndicator.swift` — Tool execution animation
- `ViewModels/ChatViewModel.swift` — UI state proxy

### Files Modified
- `ContentView.swift` — HStack wrapper + ⌘. toggle
- `AppState.swift` — aiRuntime + static shared
- `EruditeApp.swift` — Shared init, window width 1100
- `AppConfig.swift` — aiBaseURL, aiModel for custom endpoints

### Bugs Fixed
- CPU 100%: byte-by-byte + per-token re-render + markdown re-parse → throttle + plain text
- No response: `bytes.lines` swallowed SSE empty-line separators → byte-buffer approach

## Commits
- `4fee2fe` spec for ai
- `1511134` feat: ai basic
- `34944ba` support customized model server
- `25c1045` optim performance
