---
id: erudite-22
title: "Chat UX & Traceability: Resizable Panel, Tool Inspection, Usage Metadata"
status: done
priority: medium
estimate: M
---

## Objective

Polish the AI chat panel into a debuggable, comfortable workspace: a resizable
side panel, inspectable tool calls, per-turn usage/traceability metadata, and a
multiline input that stays usable during streaming. Also fix a critical render
loop and harden the tool-call loop.

## Delivered

### Resizable Side Panel
- Drag-to-resize chat panel width (clamped 240–500pt), persisted to UserDefaults
- Drag handle is a transparent overlay on the `Divider` (continuous separator,
  no broken/duplicated lines)
- Panel fills naturally instead of a fixed `minWidth` frame

### Tool-Call Inspection
- Collapsible per-message tool-call section (default collapsed, click to expand)
- Shows tool name, **input params**, and **tool result** for each call
- Selectable text (`.textSelection(.enabled)`); content-sized (no reserved
  whitespace — replaced fixed-height `ScrollView` with `Text` + `fixedSize`)

### Usage & Traceability Metadata (`TurnMeta`)
- Per-turn footer on final assistant messages: `input→output tokens`, latency
  (ms), cache hit indicator, and truncated request ID (full ID on hover)
- `x-request-id` / `request-id` captured from response headers in `AnthropicClient`
  and threaded through `AgentRuntime` → `ChatMessage.turnMeta`
- Session IDs surfaced for correlation (with AI traces from issue #21)

### Multiline Input
- `Enter` sends, `Shift+Enter` inserts newline
- Editable at all times — including during streaming (prepare the next message;
  send is gated until generation stops)

### Tool Loop Hardening
- Raised per-turn tool-call limit 5 → 10 (`maxToolRounds`)
- Inject a system hint when approaching the limit ("respond directly now without
  calling more tools") instead of abruptly cutting the turn

## Files Modified
- `Views/Main/ContentView.swift` — draggable divider + persisted `aiPanelWidth`
- `Views/AI/AIChatPanel.swift` — `messageList` uses stored `runtime.messages`
  (render-loop fix), natural panel sizing
- `Views/AI/ChatMessageView.swift` — collapsible tool-call details + `TurnMeta`
  footer (tokens/latency/cache/request-id)
- `Views/AI/ChatInputView.swift` — multiline, always-editable, Enter/Shift+Enter
- `Services/AI/AnthropicClient.swift` — capture request-id from response headers
- `Services/AI/AgentRuntime.swift` — `TurnMeta`, request-id plumbing,
  `maxToolRounds = 10`, near-limit "answer directly" hint

## Bugs Fixed
- **CPU 100% + unbounded memory (render loop):** `ForEach` bound to a *computed*
  `visibleMessages` array allocated a new array every access → `@Observable`
  marked it dirty → infinite re-render. Fixed by binding to the stored
  `runtime.messages` and filtering inside `ForEach` (`if !msg.isToolResult`).
- **Tool calls failing / hitting limit:** root-caused to the model provider
  mangling tool-call JSON (resolved by switching provider/endpoint); kept the
  raised limit + graceful near-limit hint as defense.
- **Sidebar separator broken & tool-detail whitespace:** see Delivered.

## Key Design Decisions
- `ForEach` must always bind to a stored `@Observable` property, never a computed
  array (documented in `development.md` → SwiftUI performance pitfalls).
- Streaming text renders as plain `Text`; markdown is parsed once on the final
  message (per-frame parse is too expensive during streaming).
- Traceability data (IDs/tokens/latency) is captured at the HTTP boundary and
  surfaced both in the chat UI and the AI trace table (issue #21).
