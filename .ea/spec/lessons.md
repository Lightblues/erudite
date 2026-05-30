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

## 2026-05-30 — Word management overhaul (issue #24)

### List performance: don't decode 13K JSON blobs to render rows
- **Symptom:** Library felt laggy; every keystroke in the search field re-ran
  `String.contains` over 13K decoded `Word` structs, and the tier picker called
  `words.filter { ... }.count` four times per render.
- **Root cause:** The list view was reading **fat models** (`[Word]`) when it
  only needed five fields per row.
- **Fix:** Introduced a `WordSummary` projection populated directly from SQL via
  `json_extract(data, '$.definitions[0].chinese')` and a `LEFT JOIN` on
  `reviewCard`. Filtering, sorting, search, pagination all run in SQLite.
- **Takeaway:** When list rows need a few fields out of a fat blob, don't decode
  the blob — project the fields you need at the SQL boundary. The "data path
  fork" (summaries for lists, full models for details) is cheap to maintain and
  pays for itself in two orders of magnitude on cold-open performance.

### Trust but verify, especially around navigation
- **Symptom:** After refactoring Library/Plan to use `NavigationLink(value:)` +
  `.navigationDestination(for:)`, clicking a row did nothing. No error, no log.
- **Root cause:** `NavigationSplitView`'s detail column doesn't supply its own
  `NavigationStack`. `.navigationDestination` had no stack to register against,
  so links became silent no-ops.
- **Fix:** Wrap each list view in its own `NavigationStack`.
- **Takeaway:** "Build SUCCEEDED" is necessary, not sufficient. SwiftUI's
  navigation modifiers fail open — they don't crash, they just don't do
  anything. Always run the app and click the link before claiming the feature
  works.

### `.onKeyPress(.escape)` needs focus; popovers don't have it
- **Symptom:** Esc inside a `WordPopoverView` did nothing. Esc inside a pushed
  `WordDetailView` (mostly a `ScrollView`) also did nothing.
- **Root cause:** `.onKeyPress` only fires on the focused view. SwiftUI does
  not auto-focus popover contents, and `ScrollView`s have no natural focus
  target. `.focusable()` set on a non-control view is also flaky.
- **Fix:** Hidden Button + `.keyboardShortcut(.cancelAction)`:
  ```swift
  .background(
      Button("Dismiss") { onDismiss?() }
          .keyboardShortcut(.cancelAction)
          .opacity(0).frame(width: 0, height: 0)
          .accessibilityHidden(true)
  )
  ```
  The Button is in the view tree, so the shortcut is installed for as long as
  the view is visible. No focus required.
- **Takeaway:** For Esc inside any container that doesn't naturally hold focus
  (popovers, sheets without text fields, ScrollViews), `.keyboardShortcut`
  beats `.onKeyPress` every time. Focus-dependent shortcuts are a footgun.

### Don't drop events to "yield" the keyboard
- **Symptom:** After my first attempt to coordinate popover Esc with the
  flashcard host, *all* keys stopped working whenever a popover briefly opened
  (and sometimes after Typing's Space toggle).
- **Root cause:** I had `KeyCaptureView.keyDown` return early when
  `popoverDepth > 0`. If the popover lifecycle didn't fire `onDisappear`
  cleanly, depth got stuck above zero and the keyboard locked. Even when it
  did fire, the brief depth>0 window meant Esc bypassed both the popover
  *and* the host.
- **Fix:** `keyDown` always forwards. Only the focus *re-grab* in
  `resignFirstResponder` and `windowDidBecomeKey` is suspended while
  `popoverDepth > 0`. Events flow normally; only the AppKit-level
  firstResponder tug-of-war pauses, letting the popover's
  `.keyboardShortcut(.cancelAction)` actually receive Esc.
- **Takeaway:** When two systems compete for the keyboard, **never solve it by
  dropping events**. Solve it at the focus layer (who *owns* firstResponder),
  not the event layer (who *receives* keys).

### "Open in another tab" kills sessions
- **Symptom:** A popover's "Open in Library" button would tab-switch and the
  Typing session was gone.
- **Root cause:** Switching tabs detaches the host view, firing `onDisappear`
  → `endSession()` on the typing/flashcard view model.
- **Fix:** A global modal sheet (`AppState.detailSheetWordId` driving
  ContentView's `.sheet`) hosts the full `WordDetailView` on top of the
  current tab. The host stays mounted; the session stays alive.
- **Takeaway:** "Show details somewhere else" should never mean "switch tabs"
  if the current tab owns running state. Modal-on-top is the right shape for
  ephemeral deep-dives.

---

## Cross-cutting principles

| Theme | Principle |
|-------|-----------|
| SwiftUI perf | Re-render frequency × per-render work. Throttle the source; keep `body` cheap; never feed `ForEach` a computed array. |
| List rendering | Don't decode fat models to render thin rows. Project the fields you need at the SQL boundary. |
| Focus | One source of truth (`focusZone`); derive both layers from it; use AppKit for mouse-driven focus. Never short-circuit event delivery to "yield" the keyboard — yield at the focus layer instead. |
| Esc handling | Hidden `Button` + `.keyboardShortcut(.cancelAction)` for any container without a natural focus target. `.onKeyPress(.escape)` is fragile. |
| Navigation | "Build SUCCEEDED" doesn't mean it works. SwiftUI navigation fails open — always click the link before claiming done. |
| Modal vs tab switch | Show ephemeral deep-dives in a modal sheet, not a tab switch — preserves running session state. |
| Persistence | Store the full structured form, not a render projection. |
| AI providers | Make a configurable base URL/model; suspect provider fidelity for tool-call failures; degrade gracefully at limits. |
| Observability | Tracing/IDs/usage + an in-app debug panel are not optional for a self-built agent. |
| Lifecycle triggers | Combine count thresholds with lifecycle-event flushes for unreliable "end of X" events. |
| Concurrency | Under default-MainActor isolation, pure value types and cross-thread services must be explicitly `nonisolated`; SwiftUI errors against sibling vars are usually downstream symptoms — fix the upstream type first. |
