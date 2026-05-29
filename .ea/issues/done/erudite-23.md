---
id: erudite-23
title: "Focus & Keyboard Interaction Model (Main ↔ Chat Zones)"
status: done
priority: high
estimate: M
---

## Objective

Make keyboard focus behave deterministically across the app's two interaction
zones — the **main study area** (Flashcard/Typing) and the **AI chat panel** —
so the user can fluidly switch between studying and chatting with the agent.

Target model:
- `⌘.` moves focus into the chat input (opening the panel if needed)
- `Esc` (from chat) hands the keyboard back to the study area
- Clicking a region focuses that region (type-to-input in chat; resume study in main)

## Context

A macOS window has exactly one `firstResponder`. Two systems competed for it:
`KeyCaptureView` (an `NSView` that force-grabs focus for reliable Flashcard/Typing
shortcuts) and the chat `TextEditor` (`@FocusState`). The previous coordination
flag (`isChatInputActive`) was *derived from* the TextEditor's focus state, which
created feedback loops, raced on panel open, and could not react to mouse clicks.

Two persistent bugs motivated a rewrite:
1. Opening the panel via shortcut did not focus the input (focus set before the
   underlying `NSTextView` was in the window; worsened by the entrance transition).
2. Clicking a selectable chat message then clicking the main area left the
   keyboard dead — `firstResponder` stranded on the message's `NSTextView`, with
   nothing to make `KeyCaptureView` reclaim it.

## Delivered

### Single Source of Truth
- `AppState.focusZone (.main | .chat)` — both `KeyCaptureView.isActive` and chat
  input focus derive from it (no feedback loop)
- `focusChat()` / `focusMain()` as the only mutators
- `chatFocusNonce` — forces input re-focus even when zone is already `.chat`
  (e.g. clicking a message must pull focus back to the input)

### Window-Level Click Routing
- `NSEvent` local `.leftMouseDown` monitor routes every click by geometry:
  inside chat panel frame → `focusChat()`, else → `focusMain()`, *before* dispatch
- `ChatRegionTracker` reports the panel frame (window base coords);
  `MainWindowAccessor` scopes the monitor to the main window
- Title-bar/toolbar strip excluded so the `⌘.` button can read `focusZone`

### AppKit-Level Recovery
- `KeyNSView` registers itself as `AppState.activeKeyCapture` while active
- `focusMain()` calls `activeKeyCapture.grabFocus()` to directly reclaim a
  stranded `firstResponder`
- Async `makeFirstResponder` calls guarded with `isActiveCapture` (don't steal
  focus back after the zone flips to `.chat`)

### Robust Chat Input Focus
- Driven by `focusZone` / `chatFocusNonce` (replaces the old `focusTrigger` /
  `resignTrigger` bindings)
- `focusInput()` toggles `@FocusState` false→true on the next runloop to survive
  the panel transition and recover from selection theft

### Focus-Aware `⌘.`
- Hidden → show + focus chat; shown & focus in main → move focus to chat;
  shown & focus in chat → hide + return to main
- `Esc` in chat → `focusMain()`

## Files Created (1)
- `Views/Components/FocusSupport.swift` — `ChatRegionTracker`, `MainWindowAccessor`,
  `MouseMonitorHolder`

## Files Modified (6)
- `App/AppState.swift` — `FocusZone`, `focusZone`, `chatFocusNonce`,
  `activeKeyCapture`/`chatPanelFrame`/`mainWindow`, `focusChat()`/`focusMain()`;
  removed `isChatInputActive`
- `Views/Components/KeyCaptureView.swift` — register `activeKeyCapture`,
  `grabFocus()`, fire-time `isActiveCapture` guards
- `Views/AI/ChatInputView.swift` — focus from `focusZone`/`chatFocusNonce`,
  `focusInput()` retry, `Esc` → `focusMain()`
- `Views/AI/AIChatPanel.swift` — drop trigger bindings, add `ChatRegionTracker`,
  `focusChat()` on popover dismiss / session switch
- `Views/Main/ContentView.swift` — install mouse monitor, focus-aware `⌘.`,
  `MainWindowAccessor`
- `Views/Study/{StudyView,TypingView}.swift` — `isActive = (focusZone == .main)`

## Acceptance
- [x] `⌘.` opens the panel and the input is immediately typeable
- [x] Click chat history (text/blank) → typing goes to the input
- [x] Click the main study area → keyboard immediately controls Flashcard/Typing
- [x] `Esc` from chat returns to studying
- [x] No stranded-focus dead keyboard after selecting message text
- [x] `xcodebuild build` succeeds

## Notes
- Full design captured in `.ea/spec/interaction-model.md`; the multi-round
  debugging history is in `.ea/spec/lessons.md`.
- **Known trade-off:** clicking a chat message pulls focus to the input (so typing
  always works), which can interrupt drag-selecting message text for copy. If copy
  becomes important, restrict the chat-region grab to blank/non-text areas.
