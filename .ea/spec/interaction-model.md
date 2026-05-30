# Interaction & Focus Model

How keyboard, mouse, and focus are coordinated across the app's two interaction
zones (the **main study area** and the **AI chat panel**). This is the hardest
part of the macOS UI layer, because two independent focus systems compete for a
single OS-level resource.

---

## 1. The Core Problem

A macOS window has exactly **one** `firstResponder` (an AppKit / `NSView`-level
rule). All key events go to that single view. But Erudite has two regions that
both want the keyboard:

| Zone | Keyboard need | Implementation | Why |
|------|---------------|----------------|-----|
| **Main** (Flashcard / Typing) | Full keyboard control (Space, 1-4, letters, arrows) | `KeyCaptureView` (NSView, force-grabs firstResponder) | SwiftUI `@FocusState` + `.onKeyPress` is unreliable on macOS (loses focus after popovers/buttons, system beeps on unhandled keys) |
| **Chat** (AI panel) | Text input (IME, cursor, selection) | `TextEditor` + `@FocusState` (SwiftUI) | Needs a real text editor |

These live at **different layers** and cannot both hold focus:

```
KeyCaptureView (AppKit layer)            TextEditor / @FocusState (SwiftUI layer)
    │ window.makeFirstResponder(self)         │ isFocused = true
    │ re-grabs on resign                       │ underlying NSTextView
    └──────── compete for window.firstResponder ────────┘
```

The previous design derived a coordination flag (`isChatInputActive`) *from* the
TextEditor's focus state. That was fragile: it created feedback loops, had timing
races on panel open, and — critically — could not react to **mouse clicks**
(clicking a selectable message moved firstResponder to that text and stranded the
keyboard with no way to recover).

---

## 2. The Model: One Source of Truth + Click Routing

The keyboard belongs to exactly one **focus zone** at a time, stored as a single
authoritative value. Everything else is derived from it.

```
                      ┌─────────────────────────────┐
                      │   AppState.focusZone         │  ← single source of truth
                      │   .main  |  .chat            │
                      └──────────────┬──────────────┘
            ┌────────────────────────┼────────────────────────┐
            ▼                        ▼                         ▼
   KeyCaptureView.isActive   ChatInputView focus      (drives both, no feedback)
   = (focusZone == .main)    = (focusZone == .chat)
```

A **window-level mouse monitor** is what makes "click a region → keyboard goes
there" deterministic — it updates `focusZone` *before* the click is dispatched,
so focus follows the pointer regardless of what the click lands on.

### State in `AppState`

| Property | Type | Purpose |
|----------|------|---------|
| `focusZone` | `enum { main, chat }` | Single source of truth for keyboard ownership |
| `chatFocusNonce` | `Int` | Bumped to (re)request input focus even when zone is already `.chat` (e.g. clicking a selectable message must pull focus back to the input) |
| `activeKeyCapture` | `weak KeyNSView?` (`@ObservationIgnored`) | AppKit handle so `focusMain()` can directly re-grab firstResponder |
| `chatPanelFrame` | `CGRect` (`@ObservationIgnored`) | Chat panel frame in window base coords; `.zero` when hidden |
| `mainWindow` | `weak NSWindow?` (`@ObservationIgnored`) | Scopes the mouse monitor to the main window only |

```swift
func focusChat() {            // → AI input
    focusZone = .chat
    chatFocusNonce &+= 1       // forces re-focus even if already .chat
}

func focusMain() {            // → study area
    focusZone = .main
    activeKeyCapture?.grabFocus()   // directly reclaim firstResponder
}
```

---

## 3. Components

| Component | File | Role |
|-----------|------|------|
| `AppState.FocusZone` | `App/AppState.swift` | The source of truth + `focusChat()` / `focusMain()` |
| `KeyCaptureView` / `KeyNSView` | `Views/Components/KeyCaptureView.swift` | Main-area key capture; registers itself as `activeKeyCapture` when active; `grabFocus()` reclaims firstResponder |
| `ChatInputView` | `Views/AI/ChatInputView.swift` | Drives `@FocusState` from `focusZone` / `chatFocusNonce`; `focusInput()` retries via false→true toggle |
| `ChatRegionTracker` | `Views/Components/FocusSupport.swift` | Background probe reporting `chatPanelFrame` (window coords) |
| `MainWindowAccessor` | `Views/Components/FocusSupport.swift` | Captures `mainWindow` |
| `MouseMonitorHolder` | `Views/Components/FocusSupport.swift` | Owns the `NSEvent` local monitor token / teardown |
| Mouse monitor | `Views/Main/ContentView.swift` | Routes every left-click to `focusChat()` / `focusMain()` |

### KeyCaptureView contract

- `acceptsFirstResponder = true`, force-grabs on becoming active.
- `hitTest → nil`: mouse events **pass through** to the SwiftUI layer underneath.
- `keyDown` never calls `super` for unhandled keys → no system "bonk".
- Re-grabs on `resignFirstResponder` / `windowDidBecomeKey` **only while active**
  (`isActiveCapture`); yields completely when `focusZone == .chat`.
- Registers/deregisters as `AppState.activeKeyCapture` based on active state.
- Async re-grabs are guarded at fire-time (`guard isActiveCapture`) to avoid
  stealing focus back after the zone flips to `.chat`.

### ChatInputView focus

- `onAppear` → if `focusZone == .chat`, `focusInput()` (handles panel-open).
- `onChange(chatFocusNonce)` → `focusInput()` (handles ⌘. / chat clicks / popover
  dismiss / session switch).
- `onChange(focusZone == .main)` → resign.
- `focusInput()` toggles `isFocused` **false → true** on the next runloop, which
  forces SwiftUI to re-assert focus even when it's already `true` (recovers from
  selection theft) and survives the panel's entrance transition.

---

## 4. Click Routing (the mouse monitor)

Installed once via `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)`:

```
left mouse down
   ├─ not the main window?            → ignore (Debug window, etc.)
   ├─ in title bar / toolbar strip?   → ignore (let the ⌘. button read focusZone)
   ├─ inside chatPanelFrame?          → focusChat()   (pull keyboard to input)
   └─ otherwise (main area)           → focusMain()   (reclaim study keyboard)
```

- Region is decided by geometry (`chatPanelFrame.contains(locationInWindow)`),
  both in the window's base coordinate system, so no coordinate conversion is
  needed.
- The monitor **returns the event** unchanged — normal dispatch still happens
  (buttons, selection, the TextEditor caret all keep working).
- The title-bar/toolbar exclusion (`y > window.contentLayoutRect.maxY`) prevents
  the monitor from pre-empting the ⌘. toggle button, which itself reads
  `focusZone`.

---

## 5. Focus Transitions

| Event | Result |
|-------|--------|
| `⌘.` (panel hidden) | Show panel + `focusChat()` |
| `⌘.` (panel shown, focus in main) | `focusChat()` (move focus, keep panel) |
| `⌘.` (panel shown, focus in chat) | Hide panel + `focusMain()` |
| `Esc` (chat input focused) | `focusMain()` → resume study |
| Click anywhere in chat region | `focusChat()` → keyboard to input |
| Click anywhere in main region | `focusMain()` → keyboard to study |
| Click a selectable chat message | `focusChat()` (nonce bump re-grabs input) |
| Switch / create session, popover dismiss | `focusChat()` |
| Tab switch to Flashcard/Typing | `KeyCaptureView` active iff `focusZone == .main` |

---

## 6. Keyboard Shortcuts

| Shortcut | Action | Scope |
|----------|--------|-------|
| `⌘.` | Focus chat / move focus / hide (see transitions) | Global |
| `Esc` | Chat → return to study | Chat input focused |
| `Enter` | Send message | Chat input focused |
| `Shift+Enter` | Newline | Chat input focused |
| `Space` | Toggle reveal (Flashcard) / word card (Typing) | Main, focusZone == .main |
| `1-4` / `jkl;` | Rate Again/Hard/Good/Easy | Flashcard |
| `←` / `→` | Prev / Skip | Main |
| `r` | Replay pronunciation | Flashcard |
| `q` | End session | Flashcard |
| `Tab` | Cycle hide mode | Typing |
| Letters | Type input | Typing |
| `Esc` | Dismiss popover / pop pushed WordDetail / dismiss detail sheet / clear Library list selection | Word UI |
| `⌘O` | Open the focused popover word in a global detail sheet | Word popover |
| `⌘F` | Focus Library search field | Library |
| `↑` / `↓` | Move Library list selection (split mode) | Library |
| `⌘⇧D` | Debug panel | Global |

---

## 7. Word UI Keyboard (popovers, detail, sheet)

A second focus story sits on top of the chat/main split: word popovers,
the pushed `WordDetailView`, and the global "Show details" sheet. They are
not tied to `focusZone` but they do interact with `KeyCaptureView`.

### `popoverDepth` — the focus tug-of-war fix

`AppState.popoverDepth: Int` (`@ObservationIgnored`) tracks how many word
popovers are visible. Bumped in `onAppear` / decremented in `onDisappear`
of every word popover (`WordPopoverView`, `NotFoundPopoverView`).

`KeyCaptureView` reads it but **never drops events** based on it. Only the
focus *re-grab* is suspended:

- `keyDown` always forwards to `onKeyDown`. Events are never silently
  swallowed.
- `resignFirstResponder` and `windowDidBecomeKey` skip the async
  `makeFirstResponder(self)` call when `popoverDepth > 0`. This lets the
  popover keep firstResponder (so its keyboard shortcuts fire) without
  KeyCaptureView snatching it back a runloop later.

When the popover closes, depth returns to 0, and the next focus
notification (or click) restores normal behavior. **Never short-circuit
`keyDown` based on `popoverDepth` — it strands the keyboard if depth gets
stuck above zero.**

### Hidden-Button + `.keyboardShortcut(.cancelAction)` for Esc

`.onKeyPress(.escape)` requires the view to hold focus. Inside popovers,
ScrollViews, and other containers without a natural focus target, that
focus is unreliable — Esc silently no-ops. The reliable pattern is:

```swift
.background(
    Button("Dismiss") { onDismiss?() }
        .keyboardShortcut(.cancelAction)   // Esc on macOS
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
)
```

The Button is part of the view tree, so the shortcut is installed for as
long as the view is visible. No focus required. Used by:

- `WordPopoverView` and `NotFoundPopoverView` (Esc dismiss).
- `WordDetailView` when `escapeBehavior == .push` (Esc pops the
  `NavigationStack`).

### "Show details" sheet (no tab switching)

A popover's `Cmd+O` (or "Show details" footer button) calls
`AppState.showWordDetailSheet(wordId)`. `ContentView` mounts a global
`.sheet` that hosts a `NavigationStack { WordDetailView(.push) }`. This
deliberately doesn't switch tabs, so an in-progress
Flashcard / Typing / chat session stays alive. Esc / [Done] dismisses.

The earlier "Open in Library" tab-jump approach was abandoned because
switching tabs fired `onDisappear` on the host view — killing study
sessions in flight.

### `WordDetailView.escapeBehavior`

Same view, two host modes:

- `.push` — pushed onto a `NavigationStack` (Plan, narrow Library, detail
  sheet). The hidden-Button shortcut dismisses via
  `@Environment(\.dismiss)`.
- `.embedded` — rendered inline as the right pane in split-mode Library.
  The host (LibraryView) owns Esc — it clears the list selection. The
  detail view itself ignores Esc to avoid double-actions.

---

## 8. Design Notes & Trade-offs

- **Why a window-level monitor instead of SwiftUI gestures?** SwiftUI `onTapGesture`
  can't reliably detect "click on empty area" without eating selection/drag, and
  it can't see clicks consumed by child controls. A local `NSEvent` monitor sees
  every click, decides the zone, and passes the event through untouched.
- **Why `chatFocusNonce` and not just `focusZone`?** Clicking a selectable message
  while the zone is *already* `.chat` must still yank focus back to the input.
  An `onChange(focusZone)` wouldn't fire (no value change); the nonce always does.
- **Why force-grab in `KeyNSView` (AppKit) instead of via SwiftUI?** When focus is
  stranded on a message `NSTextView`, nothing in the SwiftUI layer triggers a
  firstResponder change. `focusMain()` calls `activeKeyCapture.grabFocus()`
  directly at the AppKit layer to guarantee recovery.
- **Known trade-off — text selection in chat:** clicking a message pulls focus to
  the input (so typing always works), which can interrupt drag-selecting message
  text for copy. If copy becomes important, restrict the chat-region grab to
  blank/non-text areas only.
- **`@ObservationIgnored` on geometry/window handles:** `chatPanelFrame`,
  `mainWindow`, and `activeKeyCapture` are plumbing for the monitor, not UI state.
  Marking them ignored avoids spurious view invalidation / render loops.

---

## 9. Don'ts (regressions to avoid)

- ❌ Don't derive the coordination flag from `@FocusState` — it can't see clicks
  and creates feedback loops. Drive everything from `focusZone`.
- ❌ Don't auto-focus the input from `onAppear` alone — the underlying `NSTextView`
  isn't in the window yet during the panel transition. Retry on the next runloop.
- ❌ Don't let `KeyCaptureView` re-grab while `focusZone == .chat` — guard every
  async `makeFirstResponder` with `isActiveCapture`.
- ❌ Don't make `⌘.` a blind visibility toggle — it must be focus-aware so that
  pressing it while studying (panel already open) moves focus *into* chat.
- ❌ Don't short-circuit `KeyCaptureView.keyDown` on `popoverDepth > 0` — events
  must always be forwarded; only the focus re-grab is suspended. Dropping events
  strands the keyboard if depth ever gets stuck above zero.
- ❌ Don't use `.onKeyPress(.escape)` to dismiss popovers / detail pages — focus
  is unreliable inside popovers and ScrollViews. Use a hidden Button with
  `.keyboardShortcut(.cancelAction)` instead.
- ❌ Don't switch tabs to "show a word's full detail" — `onDisappear` on the host
  kills study sessions in flight. Use the global `.sheet` route via
  `AppState.showWordDetailSheet`.
