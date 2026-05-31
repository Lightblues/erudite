# Feature Design

## 1. Today / Home

The entry point when opening the app. Shows progress at a glance plus the
list of **study units** the user can pick from today — never just counts.

### Layout (current)

```
┌── Today ────────────────────────────────────────────────────┐
│                  Good morning!                              │
│                  Saturday, May 31                           │
│                                                             │
│  📕 GRE Core 500 ▼                                          │
│  ✓ Learned 234   ↻ Due 12   + Remaining 266                │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 47%               │
│                                                             │
│  Today's plan                          4 units · ~22 min    │
│  ┌────────────────────────────────────────┐                 │
│  │ ↻ Reviews · 1     12 cards · ~5 min  ›│                 │
│  │ ↻ Reviews · 2     12 cards · ~5 min  ›│                 │
│  │ ↻ Reviews · 3      9 cards · ~4 min  ›│                 │
│  │ + New words       12 cards · ~6 min  ›│                 │
│  │ 📕 GRE 3000 · Unit 1                  ›│  ← optional     │
│  └────────────────────────────────────────┘                 │
│  ─────────────────────────────────────────────────────────  │
│                                                             │
│  ┌─ Reviews (12) ───────────┐  ┌─ New (10) ──────────────┐ │
│  │ aberrant     1d late      │  │ obstreperous            │ │
│  │ coalesce     today        │  │ perfidious              │ │
│  │ equivocate   today        │  │ quintessence            │ │
│  │ ⋯ scroll for more        │  │ ⋯ scroll for more       │ │
│  └──────────────────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

- **Today's plan** lists pre-built `StudyUnit` objects from
  `StudyQueueBuilder.buildTodayUnits()`: due cards sliced into
  `unitSize`-card chunks, plus an optional New Words unit (cap = unitSize),
  plus an optional Book Chapter shortcut from the active book. Tapping a
  row opens `UnitPreviewView` (sheet) — the user scans the words for ~30s,
  then picks **Flashcard** or **Typing** to consume the unit. Both paths
  consume the same pre-resolved cards/words; only the interaction differs.
- **Two-column preview** (Reviews / New) below: each row shows spelling +
  POS + first Chinese def. Reviews rows include a relative due-date label
  computed at local-day boundaries (`today` / `1d late` / `in 2d`).
- **Tapping a row** opens a `WordPopoverView` for a quick peek.
- **Empty columns** show inline "No reviews due" / "No new words queued"
  instead of a separate banner.
- Rows render from lightweight `WordSummary` projections (no full-word
  JSON decoded for the list). See `data.md` for the projection model.

### Unit Preview (sheet)

```
┌── Reviews · 1 ─────────────────────────┐
│ ↻  Reviews · 1                          │
│   12 cards · ~5 min                     │
│   Take 30 seconds to scan these         │
│ ─────────────────────────────────────── │
│   1  aberrant   /æˈber.ənt/  adj 异常的 │
│   2  coalesce   /koʊəˈles/   v   联合   │
│   3  equivocate ...           v   含糊 │
│   ⋯                                     │
│ ─────────────────────────────────────── │
│         [Cancel]  [Typing]  [Flashcard] │
└─────────────────────────────────────────┘
```

The unit preview is the GRE-3000 paper-book moment: see the words you're
about to learn, decide whether you're committing, then drop in. Esc /
Cancel returns without locking the user into a session. **Flashcard** is
the default action (Return). **Typing** is right next to it because the
two paths consume the same `StudyUnit` — switching mode mid-session is
just "back to preview, pick the other one."

### AI Daily Briefing (planned, not yet built)
- Summarizes yesterday's progress
- Highlights focus areas ("yesterday's 'criticism' word group had low accuracy")
- Streak days, mastered count, projected completion date

---

## 1b. Plan

A second top-level tab dedicated to *future* work. Today is "what now?";
Plan is "what's coming?"

### Layout (four sections, top → bottom)

```
┌── Plan ────────────────────────────────────────────────────┐
│  Roadmap                                                    │
│  GRE Core 500 ━━━━━━━━━━━━●━━━━━━━━━━━━━ 234/500 (47%)     │
│  At 10 new/day, ETA ~27 days.                               │
│  Estimate varies with review accuracy.                      │
│                                                             │
│  7-Day Workload                                             │
│   30 ┤                                                      │
│   20 ┤   ▆▆                                                 │
│   10 ┤▄▄ ▆▆ ▆▆ ▅▅ ▃▃ ▂▂ ▂▂                                  │
│      └─Mon Tue Wed Thu Fri Sat Sun                          │
│                                                             │
│  New Words Queue (next 50)                                  │
│   235  obstreperous   adj 吵闹的                             │
│   236  perfidious     adj 背信弃义的                         │
│   ⋯                                                          │
│                                                             │
│  Due Backlog                                                │
│   ▾ Today (12)        aberrant  coalesce  …                 │
│   ▸ Tomorrow (8)                                            │
│   ▸ This week (45)                                          │
│   ▸ Later (203)                                             │
└─────────────────────────────────────────────────────────────┘
```

### Roadmap
- Progress bar against the active book; ETA in days at the daily new-word
  pace. Caveat surfaced about FSRS accuracy variance.

### 7-Day Workload
- Swift Charts `BarMark` of upcoming due-card load per day.
- Snapshot disclaimer below — every rating shifts future dates.

### New Words Queue
- Next 50 words by book sortOrder. Click to push the full WordDetailView.

### Due Backlog
- DisclosureGroups for `Overdue` / `Today` / `Tomorrow` / `This week` /
  `Later` (next 30 days). Each shows a per-bucket count and expands to
  show up to 30 words; "and N more" appears when the cap is hit.

### Note: "All Books" mode
- When no active book is selected, Roadmap hides itself; Workload / Queue /
  Backlog show global counts.

---

## 2. Learn (FSRS Study Session)

The primary learning mode. Handles both new word learning and due reviews.

### Card Layout (Front)
```
┌─────────────────────────────────────┐
│           aberrant                    │
│           /æˈber.ənt/  🔊            │
│                                      │
│  ┌─ Word Root Breakdown ──────────┐  │
│  │  ab-(away) + err-(wander) + -ant │ │
│  │  → wandering away from norm      │ │
│  └──────────────────────────────────┘│
│                                      │
│         [ Tap to reveal ]            │
└─────────────────────────────────────┘
```

### Card Layout (Back)
```
┌─────────────────────────────────────┐
│  adj. departing from the expected    │
│  偏离正常的；异常的                   │
│                                      │
│  📝 "The results were aberrant,      │
│     defying all scientific models."  │
│     — OG Practice                    │
│                                      │
│  🔗 Synonyms: anomalous, atypical    │
│  ⊕  Antonyms: normal, typical        │
│  😈 Sentiment: negative/neutral      │
│                                      │
│  💡 AI tip (personalized)            │
│                                      │
│  [Again ❌] [Hard 😐] [Good ✓] [Easy ⚡]│
│   <1min     6min     10min     4days │
└─────────────────────────────────────┘
```

### Behavior
- FSRS 4-rating system determines next review interval
- Session shows mix of: due reviews (priority) + new words (daily limit)
- Progress bar shows session completion
- AI tip on back is personalized based on history (e.g., "you confused this with abhorrent last time")

---

## 3. Review Modes

### 3a. Flashcard (抽认卡)

**When:** After initial learning, days 1-3. Quick memory check.

```
┌──────────────────────────────────┐
│         ephemeral                  │
│                                    │
│     [Know ✓]      [Don't Know ✗]  │
│     (swipe left)  (swipe right)   │
└──────────────────────────────────┘
```

- Binary judgment (know / don't know)
- "Don't know" → flip to show definition, mark for FSRS priority review
- "Know" → light reinforcement (does not fully update FSRS state)
- Faster pace than full FSRS study
- Recommended: 5-10 min/day in early stage

### 3b. Quiz (做题巩固)

**When:** After day 3+. Active recall with interference.

**Mode A: Word → Definition**
```
Q: "equivocate" 的含义是？
  A. 使平等
  B. 含糊其辞，模棱两可 ✓
  C. 相等的，等价的
  D. 大声抗议
```

**Mode B: Definition → Word**
```
Q: "to speak vaguely so as to deceive or avoid commitment"
  A. equivocate ✓
  B. prevaricate
  C. vacillate
  D. procrastinate
```

**Mode C: SE Synonym Pairing (GRE-specific)**
```
Q: Select two words with the most similar meaning:
  □ garrulous    □ laconic
  □ reticent     □ loquacious
  □ terse        □ verbose
```
Answer: garrulous + loquacious (both mean talkative)

**Quiz Design Principles:**
- Distractors are semantically related (not random) — AI-generated
- After incorrect answer: AI explains why wrong, distinguishes from correct answer
- Tracks error patterns to identify weak word clusters
- Results feed back to FSRS (wrong answers trigger earlier review)

### 3c. Typing Practice (拼写练习 — qwerty-learner style)

**When:** Building muscle memory for spelling. Complementary to passive flashcard review.

**Philosophy:** On a computer, passive card-flipping has limited retention. Typing engages motor memory and active recall simultaneously. Inspired by [qwerty-learner](https://github.com/RealKai42/qwerty-learner).

**Two entry paths** (mirror Flashcard):

1. **Unit-driven** (Today → UnitPreview → Typing): consumes the same
   `StudyUnit` Flashcard would have. `unitMode = true`.
2. **Standalone** (open Typing tab directly): persisted chapter index
   for the active book; user browses chapters freely. `unitMode = false`.

In **unitMode**, completing a typed word triggers a derived FSRS rating
(`mistakes==0 → Good`, `1–2 → Hard`, `3+ → Again`) and writes through to
`reviewCard` + `reviewLog`. Strict gate: only fires for cards where
`state != .new && dueDate <= now`, so Typing can't skip the New→Learning
bootstrap or pull future-scheduled cards forward. Standalone Typing
writes `typingLog` only — no FSRS impact.

```
┌─────────────────────────────────────────────────────────────┐
│ Ch 3/8              12/20                                ✕  │
│ Accent:[US▾] Display:[Hide Vowels▾] Error:[Retry▾] Order:[Seq▾] ☑Loop │
│─────────────────────────────────────────────────────────────│
│                                                             │
│          adj. 好斗的; 好战的                                 │
│          /bɪˈlɪdʒərənt/                                    │
│                                                             │
│        b  e  l  l  i  g  e  r  e  n  t                     │
│        ✓  ✓  ✓  _  _  _  _  _  _  _  _                     │
│                                                             │
│  ← abnormal    [Word List]    belittle →                    │
│─────────────────────────────────────────────────────────────│
│ Time: 2:34 | WPM: 12.3 | Inputs: 89 | Correct: 82 | 92%   │
│─────────────────────────────────────────────────────────────│
│ ◀ Prev Ch      ⌘R Replay  Space Card  ←→ Nav      Next Ch ▶│
└─────────────────────────────────────────────────────────────┘
```

**State Machine:**
```
idle (释义可见, 字母隐藏, "Press any key to start")
  ↓ 任意字母键/Space (消费掉, 不输入到单词)
typing (计时, 发音, 逐字母验证)
  ↓ Esc / 窗口失焦 / 切 tab
idle (暂停计时, 停止循环读音)
  ↓ 完成所有词
chapterComplete (统计页: 正确率/WPM/错误词列表)
```

**Settings (all persisted across sessions):**

| Setting | Options | Default |
|---------|---------|---------|
| Accent | US / UK | US |
| Display (hide mode) | Show All / Hide Vowels / Hide Consonants / Random (40%) / Hide All | Show All |
| Error handling | Retry Char / Reset Word | Retry Char |
| Word order | Sequential / Shuffle | Sequential |
| Loop Audio | On / Off | Off |

**Hide Mode Progression (difficulty):**
1. Show All — first pass, familiarization ★
2. Hide Vowels — intermediate ★★
3. Hide Consonants — harder ★★★
4. Random (40% hidden) — unpredictable ★★★
5. Hide All — full dictation ★★★★★

**Chapter System:**
- 20 words per chapter (from active book's sortOrder)
- Progress persisted per book (UserDefaults)
- Chapter complete page: accuracy / time / WPM + word list (errors first)
- Actions: Repeat / Dictation Mode / Next Chapter

**Sound Effects (system alert sounds):**
- Correct letter: Tink (clear keystroke)
- Wrong letter: Basso (warning)
- Word complete: Glass (achievement)

**Data Recording:**
- `typingLog` table: wordId, bookId, mistakes, duration, mode, timestamp
- Future: feed typing error patterns into FSRS weighting

**Keyboard Shortcuts:**
| Key | Action |
|-----|--------|
| Letters | Type spelling |
| Space | Show/hide full word card |
| ⌘R | Replay pronunciation |
| Tab | Cycle hide mode |
| ← | Go back to previous word |
| → | Skip current word |
| Esc | Pause (→ idle) |
| Return | Advance (after word complete) |

---

## 3e. Interactive Dictionary (交互式词典)

**When:** Anywhere English text appears — definitions, examples, mnemonics, synonyms.

**Philosophy:** Vocabulary learning is recursive. You encounter unfamiliar words *within* definitions. Instead of switching to an external dictionary, click any word for instant lookup.

**Architecture:**
- `InteractiveText` view — tokenizes text, renders each word clickable (with underline hint)
- `WordLookupService` — case-insensitive DB lookup + in-memory cache
- `WordPopoverView` — compact word card shown in `.popover(item:)`
- Fallback: Eudic URL scheme (`eudic://dict/{word}`) for words not in local DB
- Multi-layer: popover contents are also interactive (click words within definitions)

**Common Word Filter:**
- ~120 basic function words (articles, pronouns, prepositions, basic verbs) are NOT clickable
- Words ≤ 2 characters are skipped
- Only words that "look like vocabulary" get the underline + tap interaction

**Applied to:**
- StudyView: English definitions, example sentences, mnemonics
- TypingView: word card definitions
- WordDetailView: definitions, examples, mnemonics, synonyms

**Popover Content:**
```
┌──────────────────────────────────┐
│ erratic  /ɪ'rætɪk/          ✕   │
│──────────────────────────────────│
│ adj 无规律的，不稳定的；古怪的      │
│     something that does not      │
│     follow any pattern or plan   │
│                                  │
│ " His breathing was becoming     │
│   erratic.                       │
│                                  │
│ 💡 err(出错) + atic → 性格出错    │
│                                  │
│ 🔗 unstable odd volatile         │
└──────────────────────────────────┘
```

---

## 3f. Keyboard Focus System (KeyCaptureView)

**Problem:** SwiftUI's `@FocusState` + `.onKeyPress` is unreliable on macOS. Popovers, buttons, and phase transitions steal `firstResponder` and don't return it.

**Solution:** `KeyCaptureView` (NSViewRepresentable) — a transparent NSView that:
1. `acceptsFirstResponder = true` — always accepts keyboard
2. `resignFirstResponder()` → re-grabs after 1 runloop cycle (unless NSTextView needs it)
3. `windowDidBecomeKey` → re-grabs after popover dismiss
4. `hitTest → nil` → mouse events pass through to SwiftUI
5. `keyDown` never calls `super` → prevents system beep

Used by: StudyView, TypingView (any keyboard-driven view).

---

## 3g. Flashcard Mode (Current Implementation)

**State Machine:**
```
loading → studying ⇄ idle (Esc pauses, Space resumes)
              │
              └→ unitComplete (every N cards, only in legacy mode)
                                              ↘ studying  (Continue)
                                              ↘ complete   (Stop / queue empty)
```

Two entry paths:

1. **Unit-driven (primary)** — Today → UnitPreview → Flashcard. The
   `StudyUnit` is pre-resolved (cards + words prefetched). The view model
   just consumes it. `inUnitMode = true`: the entire unit IS the session,
   so the mid-session `unitComplete` check is disabled — running out of
   cards transitions directly to `.complete` (which renders the same
   summary content). Esc/Q ends the session and returns to Today.
2. **Legacy (fallback)** — `appState.startStudy(mode: .mixed)` from AI
   tools or older code paths. Builds the queue inline via
   `fetchDueCards + fetchNewCards`. `inUnitMode = false`: every
   `unitSize` ratings shows a Unit Summary card with [Continue][Stop].

In both modes, FSRS is updated inside `rate()` *before* any phase
transition, so an interrupted session loses no progress.

**Header Bar:**
- Progress: "X done · Y left" + card state badge (New/Learning/Review)
- Accent picker (US/UK, shared with Typing)
- Loop Audio toggle (3s interval, shared with Typing)

**Navigation Preview (between card and rating buttons):**
```
← previous_word    [Word List]    next_word →
```

**Keyboard Shortcuts:**
| Key | Action |
|-----|--------|
| Space | Toggle reveal (show/hide definitions) |
| 1 / j | Rate: Again (only if revealed) |
| 2 / k | Rate: Hard (only if revealed) |
| 3 / l | Rate: Good (only if revealed) |
| 4 / ; | Rate: Easy (works even without reveal — quick skip) |
| ← / p | Go back to previous word |
| → / n | Skip to next word |
| r | Replay pronunciation |
| q | End session |
| Esc | Pause → idle (or end session from .unitComplete) |
| Space / Return | (in .unitComplete) Continue to next unit |

**Mouse Operations:**
- Click card → toggle reveal
- Click rating buttons → rate and advance
- Click ← / → in navigation → go back / skip
- Click Word List → popover with full queue

**Unit Complete Card:**
- Header "Unit N complete" + "Take a breath — X cards left"
- 4 stats: Cards / Time / Accuracy / Again count
- Mini-grid of the unit's words colored by rating
- [Continue] (default action — Space/Return) and [Stop] buttons

**Session Complete Page:**
- Stats: Cards studied / Duration / Again count (whole-session totals)
- Full word list with rating color (Again=red, Hard=orange, Good=green, Easy=blue)
- "Study More" button to start new session

---

### 3d. Speed Review (极速刷词)

**When:** Later stages, vocabulary maintenance. Low cognitive load.

```
┌──────────────────────────────────┐
│   ⏱️ Speed Mode [2.5s/word] 67/100│
│                                    │
│        ┌──────────────┐           │
│        │  prodigal    │  🔊 auto  │
│        │              │           │
│        │  挥霍的;浪子  │ (after 1.5s)│
│        └──────────────┘           │
│                                    │
│    [⏭️ Next]    [⭐ Mark unfamiliar]│
│                                    │
│    ████████░░░░ 67%                │
└──────────────────────────────────┘
```

- Auto-play pronunciation → brief pause → show definition → auto-advance
- Pace adjustable: 1.5s / 2.5s / 4s per word
- Only action: mark as "unfamiliar" (triggers FSRS review)
- Suitable for commute / background reinforcement
- Lower priority: passive exposure has limited memory effect

### Mode Recommendation Engine

AI recommends the optimal mode based on:

| Signal | Recommendation |
|--------|---------------|
| Word just learned today | Flashcard |
| Word reviewed 3+ times, accuracy < 70% | Quiz (targeted) |
| Word mastered (stability > 30 days) | Speed review / skip |
| Words with common confusion pairs | SE pairing quiz |
| User has limited time ("5 min only") | Flashcard or speed |

---

## 4. Word Library (词库)

### Layout

Mail-style split when the window is wide enough (≥ 900pt), single-column
push navigation otherwise. Layout selection is automatic via `GeometryReader`.

```
┌── Library (wide) ───────────────────────────────────────────┐
│ [search] [Book ▾] [State ▾] [Sort ▾]                        │
│ ─────────────────────────────────────────────────────────── │
│  aberrant     /æˈber.ənt/ adj 异常的    Review   │ aberrant │
│  coalesce     ...          v   联合     Learning │ /æˈber/  │
│  equivocate   ...          v   含糊其辞  Review  │ ━━━━━━  │
│  garrulous    ...          adj 啰嗦的   New      │ Learning │
│  ⋯                                                │ Progress │
│                                                  │ ⋯        │
│ Showing 200 of 13,422 · [Load More]              │          │
└─────────────────────────────────────────────────────────────┘
```

### Filtering, Sorting, Search

All run as SQL — never as in-memory filtering of decoded `Word` blobs.
Backed by `WordSummary` projections; see `data.md`.

- **Search** (debounced 300ms): `LIKE` on `spelling` or first Chinese def.
- **Book filter** (defaults to active study book; two-way synced with
  `AppState.activeBookId` so Today / Plan / Library always agree on the
  current book): `INNER JOIN wordListEntry`.
- **State filter**: New / Learning / Review / Mature (Mature ≈ Review +
  stability ≥ 21d).
- **Sort**: Book Order (default when a book is selected — uses
  `wordListEntry.sortOrder`) / A→Z / Due date / Most lapses. Without a
  book picked, Book Order silently falls back to A→Z.
- **Pagination**: 200/page with a Load More button (no infinite scroll).
  An A-Z jump bar between the list and the resizable divider lets the user
  jump-paginate to any starting letter; clicking a letter forces
  alphabetical sort if not already and loads the page starting at the
  computed offset. Letters with zero matches under current filters are
  dimmed.

### Resizable split + persistent state

- Split layout uses **Mail-style proportions**: list defaults to 360pt
  (draggable 280–600pt via the divider's hit-region), detail fills the
  remainder. The list width is persisted to `UserDefaults` so it survives
  restarts.
- All Library "live state" (loaded summaries, pagination offset,
  selection, filter pickers, list pane width) lives in `LibraryState`
  (`@Observable`, owned by `AppState`). Switching tabs and coming back
  preserves position — the user doesn't snap back to "abacus" every
  time.
- The list row shows context-aware trailing labels: when sorted by Due
  Date, the trailing column shows `today` / `2d late` / `in 3d`; when
  sorted by Most Lapses, it shows `L:N` for cards that have lapsed.
- The lightbulb in row trailings is **purple, only when the user has
  authored their own mnemonic** (a `user_content` row of type
  `mnemonic`). Builtin mnemonics now have ~100% coverage so a generic
  "has mnemonic" indicator carries no signal.

The previous **Tier filter** (Core / Common / Advanced) was removed in
2026-05. The bundled `frequency` field had no authoritative GRE provenance
and 80%+ of words landed in the Advanced bucket, so the picker added
clutter without information. `Word.frequency` is still kept on the model
for backward compat — if a real importance signal becomes available
(per-book curation weights, corpus frequency rank), we can reintroduce a
filter on top of it.

### Keyboard browsing (split mode)

- `↑` / `↓` move list selection (`List(selection:)`).
- `Esc` clears selection (right pane reverts to "Select a word").
- `Cmd+F` focuses the search field.
- Selecting a row lazily fetches the full `Word` and renders
  `WordDetailView(escapeBehavior: .embedded)` in the right pane —
  the same view used elsewhere, just without its own Esc handler.

### Word List Management (planned, not yet built)
- Custom groups (user-created)
- Smart groups: "This week's mistakes", "Confusion pairs", "Low retention"
- Import: Anki .apkg, CSV/TSV, plain text word list
- Export: Anki-compatible, CSV

### Word Root Explorer (planned)
- Visual morpheme tree: select a root → see all derived words
- Root-based study sessions ("learn all bene- words together")
- Interactive: tap any segment to see other words sharing it

### Word Detail View

Sections, top → bottom:

- **Header** — spelling, IPA, frequency tier badge.
- **Learning Progress** (GroupBox at top — built):
  - State badge (`New` / `Learning` / `Review` / `Relearning`)
  - Due date in plain English (`Due in 3 days` / `Overdue by 2 days`)
  - Stat row: reps · lapses · accuracy% · stability (d) · difficulty
  - Recent ratings tape: last 8 ratings as colored chips (`✓` / `~` / `✗` / `⚡`)
  - Books containing this word as chips
- **Definitions** (English + Chinese) — interactive English text.
- **Examples** with source tags — interactive English text.
- **Mnemonics** — split into:
  - **Builtin** (yellow `lightbulb.fill`, locked) — from bundled `word.mnemonics`
  - **Yours** (purple `pencil.circle.fill`, editable + deletable) — from `user_content` table, `type='mnemonic'`
  - `[+ Add yours]` button → `MnemonicEditor` sheet
- **Synonyms** (chips, each tappable for popover lookup).
- **Word Roots** — prefix + root + suffix breakdown.
- **Info** — frequency, sentiment, tags.

#### Hosting modes (`escapeBehavior`)

- `.push` — pushed onto a `NavigationStack` (Plan, narrow Library, modal
  detail sheet). Esc dismisses via a hidden
  `Button.keyboardShortcut(.cancelAction)` (no focus required).
- `.embedded` — rendered inline as the split-Library detail pane. The
  host owns Esc (clears the list selection); the view itself ignores it.

#### "Show details" sheet

Any popover whose host isn't Library can call
`AppState.showWordDetailSheet(wordId)` to open the full `WordDetailView`
in a modal sheet on top of the current tab — keeping the active study
session alive. `Cmd+O` triggers it; `Esc` / `[Done]` dismisses.

---

## 5. Statistics Dashboard

### Daily/Weekly/Monthly Views
- New words learned
- Reviews completed
- Accuracy rate (overall + by tier)
- Time spent

### Retention Analysis
- Memory retention curve (actual vs predicted)
- Words at risk of forgetting (due soon)
- Mastery distribution (new / learning / mature)

### Weakness Analysis
- Weakest word clusters (by root family, sentiment group, etc.)
- Most-lapsed words (highest forgetting count)
- Confusion pair detection (words frequently mixed up)

### Progress Projection
- Days to complete current word list (at current pace)
- Exam countdown integration
- Streak calendar / heatmap

### AI Weekly Report
- Natural language summary of the week
- Highlights: breakthroughs, persistent struggles
- Recommendations for next week's strategy
