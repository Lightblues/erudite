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

---

## 2026-05-30 — Library v2 polish (post-erudite-24 followup)

### `row["x"] as? Int` is a trap with GRDB / Int64
- **Symptom:** Library's State filter "Review" returned the right rows in
  SQL (verified with sqlite3) but every row's badge in the UI showed
  "New". Other typed reads (UUID, String, Date) were fine.
- **Root cause:** SQLite stores integers as `Int64`. GRDB's `Row.subscript`
  is overloaded — `let x: Int? = row["x"]` goes through the typed-coercion
  path that converts Int64 → Int correctly, but `row["x"] as? Int` goes
  through `DatabaseValue` and silently returns `nil` for many values. So
  `cardState` was being read as `nil` → falling back to `.new` on the
  badge.
- **Fix:** Use the typed-annotation form everywhere (`let stateRaw: Int? =
  row["cardState"]`).
- **Takeaway:** When using GRDB, pick the typed-annotation subscript form
  for primitives. The `as? Int` shorthand only works coincidentally for
  values that happen to round-trip cleanly through `DatabaseValue` —
  trust nothing about it.

### LaunchServices "process" can outlive your `kill`
- **Symptom:** After `pkill -9` the Erudite process kept showing up in
  `pgrep` and `open` returned `_LSOpenURLsWithCompletionHandler() failed
  with error -1712`. New code paths I added clearly weren't running on
  re-launch.
- **Root cause:** `parent process: debugserver` — Xcode's LLDB had
  attached to the app and was holding it suspended. Killing the app
  process alone leaves the debugserver stub (and the kernel marks the
  process state `SX`); LaunchServices then thinks the bundle is "still
  running" and refuses to relaunch it.
- **Fix:** `kill -9 <debugserver_pid> <erudite_pid>` (or `killall
  debugserver`) before `open`-ing again.
- **Takeaway:** When verifying app behavior from the CLI without going
  through Xcode's UI, kill `debugserver` along with `Erudite`. Otherwise
  what you see is yesterday's binary.

### `INSERT OR REPLACE` would silently nuke FSRS progress
- **Symptom:** Almost shipped a "v3.0 word data upgrade" path using
  `INSERT OR REPLACE INTO word ...`.
- **Why that's broken:** SQLite implements REPLACE as DELETE-then-INSERT
  on PK conflict. `reviewCard.wordId REFERENCES word(id) ON DELETE
  CASCADE`, so the DELETE half of REPLACE would cascade and wipe every
  user's review history — invisibly, mid-launch.
- **Fix:** UPDATE existing rows by `id`, INSERT only genuinely new ones.
- **Takeaway:** When a parent table has CASCADE children, REPLACE on the
  parent is destructive. Always reach for explicit UPDATE/INSERT-IF-NOT-
  EXISTS for upgrade paths against tables with FK children.

### Tier filter without provenance was UX clutter
- **Symptom:** Library had a "Tier: Core / Common / Advanced" picker
  driven by `Word.frequency`, but the bundled distribution was 524 / 1779
  / 10838 — 83% of all words landed in "advanced" with no useful signal
  to differentiate them.
- **Fix:** Removed the picker, the `WordSort.frequency` option, and the
  C/M/A circle badge from `WordSummaryRow`. Default sort is now
  `bookOrder` (uses `wordListEntry.sortOrder` when a book is selected,
  silently falls back to alphabetical otherwise). Kept `Word.frequency`
  on the model so we can reintroduce a real importance signal later
  (corpus frequency rank, per-book curation weights) without a migration.
- **Takeaway:** A filter/sort axis is only worth surfacing if its
  cardinality and distribution are meaningfully informative. Skewed
  buckets are noise — delete them, don't leave them in "for completeness".

### Bundled data is a moving target — version it from day one
- **Context:** `words.json` started as v1.0 (sparse), then got
  ai-enriched to v3.0 (mnemonics, examples, synonyms for 99% of words).
  But `WordLoader.seedDatabaseIfNeeded()` only inserted on a fresh DB —
  so existing installs kept the v1.0 sparse data forever; v3.0 was
  effectively dead bytes for anyone past first launch.
- **Fix:** Added a `meta(key, value)` table; stamp `wordsVersion` on
  seed; on subsequent launches, if bundle version > stored version, run
  `upsertWordData([Word])` to UPDATE existing rows' `data` BLOBs in
  place. `reviewCard` / `reviewLog` / `user_content` are untouched.
- **Takeaway:** Anything that ships in the app bundle but lives in a
  user-mutable DB needs a version field on day one. Without it, every
  bundle update is invisible to anyone who isn't doing a fresh install.

---

## 2026-05-30 (cont.) — Library v3 polish

### Tab-switch resets `@State` — promote to a singleton if it must persist
- **Symptom:** Every time the user came back to Library, the list jumped
  back to "abacus" — losing scroll position, selection, and any "Load
  More" they'd done.
- **Root cause:** `LibraryView` is a SwiftUI `View` value type embedded in
  `NavigationSplitView`'s detail column. SwiftUI rebuilds it on every tab
  switch, which re-runs `.task` and resets every `@State` to its initial
  value.
- **Fix:** Promoted "live state" (loaded summaries, selection, filter
  pickers, list-pane width) to a `LibraryState` singleton owned by
  `AppState`. Views read it via `@Bindable var lib = appState.libraryState`.
  Survives tab switches; selectively persists what should outlive process
  restart (split-pane width → UserDefaults).
- **Takeaway:** `@State` in a SwiftUI View is "view-local UI state, lifetime
  tied to view identity." Anything that should outlive a tab switch
  belongs in an `@Observable` object owned by the app, not the view.

### A SwiftUI ForEach over `[Character]` doesn't compile
- **Symptom:** `ForEach(letters, id: \.self) { ... }` over `[Character]`
  errored with "no exact matches in call to initializer" / "[Character] →
  Binding<C>" / "generic parameter 'C' could not be inferred".
- **Cause:** Swift `Character` is `Hashable` but the SwiftUI overload
  resolver picks the wrong initializer. Easiest fix: feed `[String]`
  instead.
- **Takeaway:** When `ForEach` complains, try the simplest collection
  type that satisfies the same intent — usually `[String]`.

### Color foregroundStyle ternary needs both arms typed as `Color`
- **Symptom:** `foregroundStyle(active ? .secondary : .tertiary)` on Text
  failed with "result values in '? :' expression have mismatching types
  'Color' and 'some ShapeStyle'".
- **Cause:** `.secondary` resolves to a `HierarchicalShapeStyle`,
  `.tertiary` doesn't (or vice versa). The conditional needs both arms
  to be the same type. `foregroundStyle` is heavily overloaded and does
  not unify the arms.
- **Fix:** Make both sides explicit `Color` (`Color.secondary` and
  `Color.secondary.opacity(0.35)`).

### FSRS x Unit chunking — they're orthogonal
- **Context:** Adding "unit summary cards every N reviews" sounded like
  it might break FSRS scheduling.
- **Reality:** FSRS persists state inside `rate()`, before the unit
  boundary check. The unit layer only decides *when to show a summary
  card* — the queue, the schedule, the reviewLog are all unaffected.
- **Takeaway:** Treat UX chunking layers as filters/dispatchers on top of
  the underlying state machine, not as state-machine modifiers.
  Implementation cost stayed low precisely because of this separation.

### "29 missing X" in DataDiagnostics tells a real story
- **Observation:** After v3.0 upgrade ran cleanly, the new DB integrity
  view showed: 29 words without reviewCard, 29 missing chinese def, 29
  missing mnemonic. Same 29 in all three columns.
- **Explanation:** These are runtime-cached words from
  `WordLookupService` — the user clicked an unknown word while reading
  and the API filled in just the lookup fields (`spelling`, `phonetic`,
  one definition), bypassing both the bundle seed *and* the
  `createCardsForNewWords` helper. Not a regression; surfaced because
  diagnostics are now wired up.
- **Takeaway:** Integrity checks pay for themselves the moment you turn
  them on. Anomalies the human can't see in the UI become obvious in
  numbers. Even when the answer is "expected for this code path", you
  now know the count.

---

## 2026-05-31 — Unit as a domain object

### Three SQLs querying "the same thing" was a smell
- **Symptom:** Today/Plan/Flashcard/Library each had their own
  due/new query: `fetchDueSummaries`, `fetchDueCards`, `fetchDueBacklog`,
  plus the Library SELECT — four implementations, slightly different
  filters, all going to drift the moment FSRS scheduling logic moved.
- **Root cause:** No single domain concept of "the user's session today."
  Each view rolled its own slice.
- **Fix:** Introduced `StudyUnit` (a resolved chunk of cards + words +
  meta) and `StudyQueueBuilder` (the only place that constructs them).
  Today shows `[StudyUnit]`, UnitPreview shows one, Flashcard/Typing
  consume one. The summary queries (`fetchDueSummaries` etc.) survive
  for the Today preview / Plan backlog / Library because *those* views
  are about browsing, not committing — different intent, different API.
- **Takeaway:** When N views fetch "the same thing" with subtly
  different filters, that's not "they need different queries", that's
  "you don't have a domain object yet". Pull the concept up; the
  queries follow.

### Two view models converging on one data shape
- **Symptom:** `StudyViewModel` and `TypingViewModel` had completely
  separate "load my words" code: Flashcard built its queue from FSRS
  due/new, Typing paged through `wordListEntry` 20 at a time. The
  user mentally maps both to "I'm studying X words right now" but
  the engines didn't agree on which X.
- **Fix:** Added a unit-mode entry to both view models that takes a
  pre-resolved `StudyUnit`. Standalone modes preserved (legacy AI
  startStudy / Typing tab direct entry) so existing flows still work.
- **Takeaway:** When you have two interaction modes for the same
  underlying activity, the data feed should converge before the UI
  diverges. Each mode's `start(unit:)` becomes 5 lines of "install
  this queue and go".

### Typing → FSRS gate matters
- **Initial instinct:** "Typing succeeded, give the card a Good rating."
  But that would let Typing skip the New→Learning bootstrap (the user
  could type their way past every flashcard exposure cycle), and pull
  future-due cards forward (overriding scheduled retention windows).
- **Decision:** Only fire derived rating when
  `card.state != .new && card.dueDate <= now`. Mature-and-due cards
  receive the signal; everything else is silently a typingLog only.
- **Takeaway:** Cross-modal feedback into a scheduling system needs
  conservative gates. The user thinks "I just typed it!" but the
  scheduler is reasoning over a longer time horizon — let the
  scheduler win when they disagree.

---

## 2026-05-31 (cont.) — Unifying study surfaces

### Two completion screens × two view models = four bespoke layouts
- **Symptom:** Flashcard had `.complete` (party popper, "Study More")
  AND `.unitComplete` (compact mid-session card). Typing had its own
  `chapterCompleteView` (WPM, accuracy bars, errors-first list). All
  three answered the same question — "this session is over, here's
  how you did" — with three different vocabularies and field names.
- **Fix:** Unified shape `SessionResult { mode, unit, entries[],
  durationSeconds, wpm }` with computed aggregates (`accuracy`,
  `againCount`, `sortedEntries`). Single view `SessionSummaryView`
  consumes it, with `Action` callbacks letting each call site decide
  what Continue/Stop/Done mean. Three previously-independent
  ~50-line summary views collapse to one.
- **Takeaway:** When several views render a slightly-different
  summary of the same activity, find the smallest shape that
  describes ALL of them and converge on it. Typed protocol-of-shapes
  beats parallel inheritance hierarchies.

### Today's two responsibilities don't belong together
- **Symptom:** I had merged FSRS-driven review units, FSRS-driven
  new-words units, AND book chapter shortcuts under one "Today's
  plan" header. Users got three semantically different things in
  one list — system-decided homework next to user-driven exploration.
- **Fix:** "Today's plan" → "Today's homework" (FSRS-only).
  Book Chapter browsing moved out of Today entirely, into Library
  under a new Words/Chapters segmented control.
- **Takeaway:** "What does the system want me to do today" and
  "what do I want to explore in this book" are different mental
  models. Don't crowd them into one list.

### Tab landing without state should pick, not default
- **Symptom:** Clicking the Flashcard tab without first picking a
  unit on Today silently ran the legacy `start(database:mode:.mixed)`
  path — different cards from what Today preview showed, no scoping,
  no explicit choice. Same for Typing.
- **Fix:** When `currentUnit == nil`, both Flashcard and Typing render
  `UnitPickerView` instead of running the legacy path. The user sees
  the SAME unit list as Today and picks one explicitly. Standalone
  chapter-by-chapter browsing moved to Library.
- **Takeaway:** Defaulting to "do something automatically" is a
  failure of explicitness. Every entry path should land on a
  visible choice if context is missing.

### "Today's recap" was the simplest big win
- **Observation:** Adding a list of "words you touched today"
  (review ratings + typing completions, sorted worst-first) was
  ~50 lines of SQL and ~80 lines of view, and it instantly made
  Today feel like a learning *journal* instead of just a launchpad.
- **Takeaway:** Reflection surfaces are cheap and high-value.
  Whenever the data exists (we already had reviewLog + typingLog),
  showing it back to the user is almost always worth the work.

### Read-only surfaces eventually want to be operation panels
- **Symptom:** Today's recap (added in erudite-28) showed "what
  you touched today" beautifully, but the natural follow-up —
  "let me re-drill the ones I missed" — required no UI path.
  Users were stuck looking at the data.
- **Fix:** Added a checkbox per row (default-checked for the
  `needsWork` subset: Again / Hard / typing-mistakes>0) and a
  bottom CTA `[Re-review · K]` that materializes the selection
  into a `.recap`-kind StudyUnit. The same UnitPreview pipeline
  consumes it; the engine has a `skipsFSRSWriteback` gate so
  recap ratings don't disturb the schedule.
- **Takeaway:** When you build a "look at this" surface, ask
  yourself: would the user want to *act on* what they're looking
  at? A checkbox column + one CTA is often enough. The
  `Kind.recap` + `skipsFSRSWriteback` combination shows the
  pattern: rather than a parallel "practice" code path, extend
  the existing pipeline with one opt-out flag.

### Today and Plan have separable mental models — keep them apart
- **Symptom:** Today had a two-column "Reviews | New" preview
  that listed the next 50 due + next 50 new words. Plan had a
  "New Words Queue" + "Due Backlog" doing the same job. Two
  surfaces showing the same data with slightly different shapes.
- **Fix:** Removed the preview from Today entirely. Today is now
  *only* "today" (homework + recap). Plan is *only* "节奏" (overview
  + future work). The split clarifies both.
- **Takeaway:** When two surfaces overlap, ask which mental model
  each one *uniquely* answers. If they answer the same thing,
  one of them is dead weight. Today = "what now?" Plan = "what's
  coming?" — distinct enough that neither can stand for the other.

### Tab-segment beats one-scroll for divergent worklists
- **Symptom:** Plan had four sections (Roadmap, Workload chart,
  New Queue, Due Backlog with disclosure tree) stacked in one
  ScrollView. Getting to "Tomorrow" required scrolling past the
  chart every time. The disclosure tree's `▸ Today (12)` /
  `▸ Tomorrow (8)` rows asked the user to expand-the-thing-they
  -wanted before they could see it.
- **Fix:** Split Plan into a fixed top region (Roadmap + Chart)
  and a tab-segmented bottom (`[Today][Tomorrow][This Week]
  [Later][New]`, count chip per tab). Each tab's word list
  scrolls full-height in its own viewport.
- **Takeaway:** When a page has an "always-relevant overview"
  + "pick-one worklist" structure, tabs beat stacked sections.
  The overview anchors the page; tabs let each list breathe.
  Disclosure groups felt natural for nested data but added a
  click for the most common reads.

### Fixed regions only earn their pin if always-actionable
- **Symptom:** erudite-29 split Plan into a fixed top (Roadmap +
  7-Day Workload chart) and a scrolling bottom (tab worklist).
  The reasoning was "the overview is always relevant." It wasn't.
  Users glanced at the chart once per visit, then wanted the
  worklist to take the full viewport — the chart became a
  permanent screen-real-estate tax.
- **Fix:** Reverted to one ScrollView. Roadmap + Chart + Tab Bar
  + Worklist all scroll together. The user can scroll the
  chart out of the way when they want to focus on a bucket.
- **Takeaway:** Fixed regions only earn their pin if they're
  *always actionable* (a search bar, a primary CTA, a tab
  selector). "Always relevant for context" is not the same as
  "always actionable" — preview-y data should scroll like the
  rest of the page. When in doubt, default to single-scroll
  and let the user's gesture decide what to focus on.

### Sessions don't need start/end rows — gap-cluster timestamps
- **Need:** Today's activity strip wanted "how many Flashcard /
  Typing sessions today." We didn't already have session-bracket
  rows in the schema; reviewLog and typingLog only carry
  per-event timestamps.
- **Fix:** `clusterCount(times, gap: 30 * 60)` — sort timestamps,
  count "gaps ≥ 30 min" as session boundaries. Empty list = 0,
  single timestamp = 1, two events 5 min apart = 1 session, two
  events 45 min apart = 2 sessions.
- **Takeaway:** Don't add a `session` table just to count
  sessions. The data already implies the boundary; you just
  need to surface it. The 30-min gap is empirical — shorter
  than a typical "I'll practice for a bit" arc, longer than
  a quick mode-switch. Worth re-tuning later from real
  usage data, but a single number in one place is easy to
  iterate on.

### Data API surface owns the semantics; views just render
- **Pattern:** When designing `fetchTodayActivityStats`, the
  question wasn't "how do I query reviewLog from the view" but
  "what 4 numbers does Today need, and how do they all derive
  from the existing log tables?" The cluster-gap, the
  `state == 0` detection for new-word bootstrap, the
  "distinct wordIds" rule — every semantic decision lives in
  the API. The view receives a `TodayActivityStats` value and
  draws four chips.
- **Takeaway:** When CLAUDE.md says "data layer does the API,
  UI displays" — the test is: could you swap the view for an
  AppleScript dump and still understand "what happened today"
  from the API alone? If yes, the boundary is right. If the
  view has to compose two API calls or apply business rules to
  display a number, the API is too thin.

### "Modes" are usually wrong abstractions for slices
- **Symptom:** erudite-29 shipped Library with a `[Words | Chapters]`
  segmented mode toggle. Inside "Chapters" the UI was completely
  different (chapter cards instead of word rows; no search, no
  sort, no filters; sheet-based interaction). User feedback:
  "I can't see what's in each Unit, I'm picking blind. And the
  two modes don't share UI."
- **Diagnosis:** "Chapters" wasn't a different mode — it was a
  different **slice** on the same word list. We shouldn't have
  switched the whole UI; we should have added one more picker
  alongside Book / State / Sort.
- **Fix:** Removed the `viewMode` toggle entirely. Added a `Unit`
  picker in the header that sits next to Book ("All units" /
  "Unit 5 (efflorescent — embellish)"). Selecting a unit narrows
  the same word list, hides State + Sort (redundant inside one
  unit), and surfaces footer action buttons.
- **Takeaway:** When you're tempted to add a "mode toggle," ask:
  is this actually a different *view* of the data, or just a
  different *slice* of it? If a slice, add a filter, don't fork
  the UI. The smell: when both modes need search, both modes
  need filters, both modes need the same row design — they're
  the same view, you just sliced wrong.

### Action buttons in the footer eliminate "what will study consume?"
- **Symptom:** When unit study lived behind the chaptersListPane
  cards, the user had to mentally connect "the words shown in
  this picker thumbnail = the words I'll study." With the new
  Unit picker, they're already looking at the exact list.
- **Fix:** Footer buttons `[Flashcard]` `[Typing]` consume "the
  list above this footer." The slice is whatever the user
  configured: Unit + State + Search compose, and the buttons
  always operate on the visible result.
- **Takeaway:** When study/practice/action buttons sit next to a
  list, the list IS the spec. The user doesn't have to imagine
  what they're committing to — they're seeing it. This kills a
  whole class of "wait, what does this button do?" questions.

### The jump-bar belongs to alphabetical sort, not to the page
- **Symptom:** A-Z jump bar was always mounted in Library's split
  layout. Under Book Order sort, clicking 'M' triggered an
  implicit sort-flip to alphabetical, then loaded a different
  offset. Two surprises: sort changed under the user, and the
  page reflowed unexpectedly.
- **Fix:** Mount the bar only when `sort == .alphabetical`. Drop
  the implicit sort-flip in `jumpToLetter`. Now the bar's
  presence signals "alphabetical jump available"; its absence
  under Book Order is the correct UX (because by-letter jumping
  in book order is meaningless).
- **Takeaway:** UI affordances should attach to the context that
  makes them meaningful, not to the page that contains them.
  When a control needs an implicit mode-flip to "make sense,"
  it doesn't belong in that mode in the first place.
