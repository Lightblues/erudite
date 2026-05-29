# Lessons Learned (Dev Log)

A running, time-ordered log of the non-obvious pitfalls hit while building
Erudite — what broke, the real root cause, the fix, and the takeaway. Newest at
the bottom. Add an entry whenever a bug costs more than ~30 minutes or teaches
something reusable.

> Early dates are approximate (reconstructed from issue order); recent ones are exact.

---

## ~2026-05-26 — AI Companion P0 (issue #19)

### Building an agent in Swift from scratch
- **Context:** Swift has no official Anthropic/OpenAI SDK; the AI/agent ecosystem
  is thin compared to TS/Python.
- **Decision:** Implement the whole agent stack ourselves (SSE client, agent
  loop, tool registry, system prompt) for full control. No third-party agent libs.
- **Takeaway:** Self-implementation is viable and keeps us in control, but quality
  hinges on our own design — invest early in **tracing/observability** to debug it.

### Auth compatibility (official API vs proxy)
- **Symptom:** Works against one endpoint, 401/format errors against another.
- **Cause:** Official API uses `x-api-key` (+ prompt caching); proxies expect
  `Authorization: Bearer`.
- **Fix:** Support both auth schemes; allow a custom base URL in config.
- **Takeaway:** Always allow a configurable base URL + model from day one.

---

## ~2026-05-27 — Memory system (issue #20)

### Session restore only showed text
- **Symptom:** Reopening a past conversation lost all tool calls — only plain
  text came back.
- **Cause:** Persistence saved a flattened text view of messages, not the full
  block structure (`tool_use` / `tool_result`).
- **Fix:** Persist the **complete** message blocks; restore them verbatim into the
  runtime.
- **Takeaway:** Store the full structured representation, not a render-friendly
  projection. The DB is the source of truth for replay.

### Observation extraction timing
- **Problem:** Per-turn extraction is too frequent; "session end" is unreliable
  (user may keep one chat open for days; app may be killed).
- **Fix:** Extract every ≥5 turns *and* flush on app backgrounding
  (`willResignActive`). Watermark tracks what's already extracted.
- **Takeaway:** For "end of X" triggers that never cleanly fire, combine a count
  threshold with a lifecycle-event flush.

---

## 2026-05-28 — Streaming performance: CPU 100% + memory blowup

Three compounding hotspots while streaming chat responses:

1. **Byte-by-byte SSE iteration → CPU 100%.**
   - Cause: `for try await byte in bytes` — one async context switch per byte.
   - Fix: iterate `bytes.lines` (OS-buffered, line-at-a-time).
2. **Per-token markdown re-parse → memory explosion.**
   - Cause: every token did `streamingText = accumulated`, and each re-render ran
     `AttributedString(markdown:)` over the *entire* text.
   - Fix: (a) throttle UI updates to ~50ms (max ~20/s); (b) render streaming text
     as **plain `Text`**, parse markdown only once on the finalized message.
3. **`ThinkingIndicator` 50ms `Timer` → sustained CPU.**
   - Cause: a timer mutating rotation state every 50ms.
   - Fix: declarative `.animation(.linear.repeatForever)` — handled on the GPU.

- **Takeaway:** In SwiftUI, the cost is rarely the language — it's re-render
  frequency × per-render work. Throttle the source, and never do expensive parsing
  inside `body` during a high-frequency update.

---

## 2026-05-28 — Logging: "where are the files?"

- **Symptom:** Console.app showed logs (filter `site.easonsi.Erudite`), but no log
  file could be found.
- **Resolution:** Files live at
  `~/Library/Application Support/Erudite/Logs/erudite-YYYY-MM-DD.log`
  (daily rotation, 7-day retention). See issue #21.
- **Takeaway:** Document log locations in the spec; ship an in-app Debug panel
  (⌘⇧D) so you don't go hunting on disk.

---

## 2026-05-28 — Tool calls failing / hitting the call limit

- **Symptom:** Asking "what conversations have we had?" made the agent call
  `search_past_conversations` with bad params 5× in a row, then
  "(Stopped: reached tool call limit)".
- **Root cause:** The model endpoint mangled the tool-call format — confirmed it
  was an **API/provider issue** (switching to OpenRouter produced correct
  tool-call JSON).
- **Mitigations kept anyway:**
  - Raised the per-turn tool-call limit (5 → 10).
  - Inject a hint near the limit ("stop calling tools and answer directly")
    instead of hard-cutting the turn.
- **Takeaway:** When tool calls fail systematically, suspect the provider's
  function-calling fidelity before your own schema. Make limits graceful, not
  abrupt.

---

## 2026-05-28 — Traceability: session & request IDs

- **Need:** Like Claude/ChatGPT, every session/request should be traceable.
- **Added:** session IDs, request IDs captured from response **headers**, and
  per-turn token/usage metadata, all surfaced in the chat UI and AI trace table.
- **Takeaway:** Capture IDs and usage at the boundary (HTTP layer) and thread them
  through to the UI — cheap to add early, invaluable for debugging later.

---

## 2026-05-29 — The big one: SwiftUI `@Observable` + `ForEach` render loop

- **Symptom:** CPU pegged, memory climbing unbounded during chat.
- **Root cause:** `ForEach(viewModel.visibleMessages)` where `visibleMessages` is a
  **computed property** that allocates a new `[ChatMessage]` each access:
  ```
  body → read visibleMessages → new array → "data changed!" → re-render
       → read visibleMessages again → new array → ∞
  ```
  `@Observable` marks the attribute dirty on every access of a computed property
  that touches observed state.
- **Fix:** Bind `ForEach` to a **stored** property (`runtime.messages`, stable
  identity) and filter *inside* the body (`if !message.isToolResult { ... }`).
- **Takeaway:** `ForEach` must never be fed a computed array. (Fully documented in
  `development.md` → "SwiftUI + @Observable Performance Pitfalls".)

---

## 2026-05-29 — Chat panel UI polish

- **Divider line broken by the drag handle:** the resize handle was a separate
  `Rectangle` + `Divider`; merged into one `Divider` with a transparent drag
  overlay so the separator stays continuous.
- **Big empty gap under tool-call details:** caused by a fixed-height
  `ScrollView`. Replaced with `Text` + `fixedSize(vertical:)` so it sizes to
  content.
- **Input wouldn't auto-focus / lost focus after streaming:** see the focus saga
  below.
- **Takeaway:** Fixed-height scroll containers reserve space even when empty;
  prefer content-sized layout for small variable content.

---

## 2026-05-29 — Focus & keyboard model (the multi-round saga)

The longest-running problem: getting keyboard focus to behave across the main
study area and the AI chat panel. Several attempts before landing the final model.

### Why it's hard
- A window has exactly **one** `firstResponder` (AppKit rule). Two systems fight
  for it:
  - `KeyCaptureView` (NSView) — force-grabs focus for Flashcard/Typing because
    SwiftUI `@FocusState` + `.onKeyPress` is unreliable on macOS (loses focus
    after popovers/buttons; beeps on unhandled keys).
  - `TextEditor` + `@FocusState` (SwiftUI) — needed for chat text input.
- They live at **different layers** (AppKit vs SwiftUI), so they can't cleanly
  share or hand off focus.

### Failed / fragile approaches
- **`isChatInputActive` derived from `@FocusState`:** a one-way flag reverse-
  engineered from the TextEditor's focus. Created feedback loops, raced on panel
  open, and — fatally — couldn't react to mouse clicks.
- **`/` as a global "enter chat" shortcut:** collided with typing `/` into the
  input; behaved identically to `⌘.`. Removed.
- **`focusTrigger` / `resignTrigger` booleans:** toggled externally to nudge
  focus. The toggle that fired *during* panel creation was missed by `onChange`,
  so opening the panel didn't focus the input.

### Symptoms that survived until the rewrite
1. Pressing the shortcut to open the panel didn't focus the input — `onAppear`
   set focus before the underlying `NSTextView` was in the window (worsened by the
   0.2s entrance transition).
2. Click a selectable message → click the main area → **keyboard dead.** Selectable
   message text (`.textSelection(.enabled)`) is a real `NSTextView`; clicking it
   stranded `firstResponder` there, and clicking the main area didn't trigger
   `KeyCaptureView` to reclaim it (SwiftUI clicks don't move firstResponder; no
   state change → no re-grab).

### Final model (see `interaction-model.md`)
- **Single source of truth:** `AppState.focusZone (.main | .chat)`. Both
  `KeyCaptureView.isActive` and chat input focus derive from it — no feedback.
- **Window-level mouse monitor:** an `NSEvent` `.leftMouseDown` monitor routes
  every click to `focusChat()` / `focusMain()` by geometry (chat panel frame),
  *before* dispatch — so focus follows the pointer deterministically.
- **`chatFocusNonce`:** forces input re-focus even when already in `.chat` (e.g.
  clicking a message), since `onChange(focusZone)` wouldn't fire.
- **AppKit-level recovery:** `focusMain()` calls `activeKeyCapture.grabFocus()`
  directly to reclaim a stranded firstResponder.
- **Robust input focus:** toggle `@FocusState` false→true on the next runloop to
  survive both the transition and prior focus theft.

### Takeaways
- Don't reverse-engineer focus state from `@FocusState`; pick one authoritative
  value and derive everything (incl. AppKit behavior) from it.
- Mouse-driven focus on macOS needs an **AppKit-level signal** (event monitor /
  firstResponder), not SwiftUI gestures.
- Guard every async `makeFirstResponder` with a "still active?" check — focus
  intent can flip between scheduling and execution.
- Keep keyboard shortcuts that gate UI (`⌘.`) **focus-aware**, not blind toggles.

---

## 2026-05-29 — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` cascading isolation errors

Opening the project after the AI Companion work, Xcode lit up with 14 errors/warnings
clustered around `DatabaseService` and the FSRS scheduler:

- "Main actor-isolated conformance of `Word` to `Encodable`/`Decodable` cannot be
  used in nonisolated(unsafe) context" (×7, every encode/decode site)
- "Call to main actor-isolated initializer in a synchronous nonisolated(unsafe)
  context" — `ReviewCard.init`, `ReviewLog.init`, `WordBook.init` inside row→model
  conversions
- "Main actor-isolated static property `default` cannot be referenced from a
  nonisolated context" — `init(parameters: FSRSParameters = .default)`
- "`nonisolated(unsafe)` has no effect on class `DatabaseService`, consider using
  `nonisolated`"
- Bonus red herring: `StudyView.swift` reported "cannot find `navigationPreview`
  in scope" + "cannot infer contextual base in reference to member `top`" against
  private vars that were obviously defined right there.

### Root cause

The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 6.2 /
SE-0466), so every type without an explicit isolation annotation is implicitly
`@MainActor` — **including its `Codable` conformance and its `init`**. This is
correct for UI / ViewModels but wrong for pure value types (`Word`, `ReviewCard`,
`ReviewLog`, `WordBook`, `FSRSParameters`).

`DatabaseService` is `nonisolated(unsafe)` because GRDB IO must run off the main
thread. Inside `dbQueue.read/write { db in ... }`, every
`JSONDecoder.decode(Word.self, …)` and `ReviewCard(...)` call crossed an
isolation boundary that the implicit-MainActor inference had quietly erected
around our data layer.

The `StudyView` errors were **downstream symptoms**: once `Word`/`ReviewCard`
fail to type-check, the closures in `studyContent` lose all their inferred types
and SwiftUI's `@ViewBuilder` collapses, producing nonsense errors against
unrelated `private var`s in the same struct.

### Fix

Mark all pure value types `nonisolated`:

| File | Types |
|------|-------|
| `Models/Word.swift` | `Word`, `Definition`, `MorphemeBreakdown`, `Morpheme`, `MorphemeType`, `Example`, `Sentiment`, `FrequencyTier` |
| `Models/ReviewCard.swift` | `ReviewCard`, `CardState`, `Rating`, `ReviewLog` |
| `Models/WordList.swift` | `WordBook` |
| `Engine/FSRS/FSRSParameters.swift` | `FSRSParameters` |

And drop the redundant `(unsafe)`:

```swift
// before
nonisolated(unsafe) final class DatabaseService: Sendable { ... }
// after
nonisolated final class DatabaseService: Sendable { ... }
```

`xcodebuild` went from 14 diagnostics to 0; the `StudyView` errors disappeared
automatically the moment the upstream types compiled cleanly.

### Takeaways

- Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, the right mental model is:
  **UI/ViewModels stay default, pure data values + cross-thread services must be
  explicitly `nonisolated`.** The default is wrong for data types because their
  protocol conformances and inits inherit isolation too — invisible until a
  background actor tries to use them.
- `nonisolated(unsafe)` on a `Sendable` class is a code smell — it almost always
  means "I gave up; please ignore the rules". `nonisolated` (without `(unsafe)`)
  is the right answer when the class genuinely is safe.
- SwiftUI errors like "cannot find X in scope" against a sibling `private var`,
  or "cannot infer contextual base" on `.padding(.top, _)`, are usually
  **downstream symptoms** of upstream type failure. Fix the real type errors
  first; the SwiftUI noise clears itself. Don't chase them.
- The Xcode Issue Navigator can keep stale diagnostics across builds (referring
  to keywords like `nonisolated(unsafe)` you've already removed). Trust
  `xcodebuild` from the CLI, not the IDE panel — `⌘B` (or Clean Build Folder)
  re-syncs it.

---

## Cross-cutting principles

| Theme | Principle |
|-------|-----------|
| SwiftUI perf | Re-render frequency × per-render work. Throttle the source; keep `body` cheap; never feed `ForEach` a computed array. |
| Focus | One source of truth (`focusZone`); derive both layers from it; use AppKit for mouse-driven focus. |
| Persistence | Store the full structured form, not a render projection. |
| AI providers | Make a configurable base URL/model; suspect provider fidelity for tool-call failures; degrade gracefully at limits. |
| Observability | Tracing/IDs/usage + an in-app debug panel are not optional for a self-built agent. |
| Lifecycle triggers | Combine count thresholds with lifecycle-event flushes for unreliable "end of X" events. |
| Concurrency | Under default-MainActor isolation, pure value types and cross-thread services must be explicitly `nonisolated`; SwiftUI errors against sibling vars are usually downstream symptoms — fix the upstream type first. |
