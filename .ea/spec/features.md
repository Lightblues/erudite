# Feature Design

## 1. Today / Home

The entry point when opening the app. Three responsibilities, kept separate:

1. **Today's activity** — inline strip showing what's been done today
   (flashcard sessions, typing sessions, words reviewed, new words
   learned). Hidden on a 0-everything day.
2. **Today's homework** — FSRS-driven units the system says you need
   today (Reviews · 1 / 2 / N + an optional New words unit).
3. **Today's recap** — a journal of words touched today (Flashcard
   ratings + Typing completions), sorted "needs another look" first.
   Doubles as an **operation panel**: each row has a checkbox and the
   bottom CTA `[Re-review · K]` materializes the selection into a
   `.recap`-kind StudyUnit (practice mode — does NOT write back to FSRS).

**What's NOT on Today**: future-due words and the new-word queue. Those
overlap Plan and used to push recap below the fold; both now live on
Plan as tabs. **Book chapter browsing has moved to Library** (Words ↔
Chapters segmented control) — Today no longer mixes "what the system
wants" with "what you might explore".

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
│  Today's activity                                           │
│  ▭ 3 Flashcards  ⌨ 1 Typing  │  ↻ 47 Reviewed  + 5 New     │
│                                                             │
│  Today's homework                      4 units · ~22 min    │
│  ┌────────────────────────────────────────┐                 │
│  │ ↻ Reviews · 1     12 cards · ~5 min  ›│                 │
│  │ ↻ Reviews · 2     12 cards · ~5 min  ›│                 │
│  │ ↻ Reviews · 3      9 cards · ~4 min  ›│                 │
│  │ + New words       12 cards · ~6 min  ›│                 │
│  └────────────────────────────────────────┘                 │
│  ─────────────────────────────────────────────────────────  │
│                                                             │
│  Today's recap                          4 / 8 selected      │
│  ┌────────────────────────────────────────────────────────┐│
│  │ ☑  [Again]   sycophant   阿谀奉承的人               × 2 ││
│  │ ☑  [Hard ]   ephemeral   短暂的                        ││
│  │ ☑  [3 miss]  bucolic     田园的                        ││
│  │ ☑  [Hard ]   torpor      迟钝                          ││
│  │ ☐  [Good ]   plethora    过多                          ││
│  │ ☐  [Easy ]   austere     朴素的                        ││
│  │ ☐  [Typed]   nadir       最低点                        ││
│  │ ☐  [Good ]   apex        顶峰                          ││
│  └────────────────────────────────────────────────────────┘│
│  [Select needsWork (4)]              [↺ Re-review · 4]      │
└─────────────────────────────────────────────────────────────┘
```

- **Today's homework** lists pre-built `StudyUnit` objects from
  `StudyQueueBuilder.buildTodayUnits()`: due cards sliced into
  `unitSize`-card chunks, plus an optional New Words unit (cap = unitSize).
  Tapping a row opens `UnitPreviewView` (sheet) — the user scans the
  words for ~30s, then picks **Flashcard** or **Typing** to consume the
  unit. Both paths consume the same pre-resolved cards/words; only the
  interaction differs.
- **Today's activity** strip — sourced from
  `DatabaseService.fetchTodayActivityStats()`. Four numbers since
  local-day start:
    - `flashcardSessions` / `typingSessions` — gap-clustered with a
      30-min threshold (events less than 30 min apart belong to the
      same session). No explicit session start/end rows in the DB.
    - `wordsReviewed` — distinct wordIds rated today (any rating).
    - `newWordsLearned` — distinct wordIds whose rating today was
      given on a `.new`-state card (reviewLog.state == 0 → bootstrap
      rating, the moment we count the word as introduced).
  All aggregation lives in the data API; the view chip strip is purely
  presentational. Hidden when all four numbers are 0.
- **Today's recap** lists words touched today (Flashcard rating + Typing
  completion), sorted by `pressingScore` (Again > Hard > many-mistakes >
  Good > Easy). Each row carries:
  - Checkbox, default-checked for `needsWork` rows (Again / Hard /
    mistakes>0). User can untick or tick freely.
  - Pressing-signal badge (Again / Hard / N miss / Good / Easy / Typed)
  - Spelling + first Chinese def + attempt count if > 1
  - Tapping the row body opens a `WordPopoverView` for a quick peek.
- **Bottom CTA**: `[Re-review · K]` materializes the selected entries
  via `StudyQueueBuilder.buildRecapUnit` into a `.recap`-kind unit and
  opens UnitPreview. Sessions started this way do NOT write back to
  FSRS — recap is "practice mode," not a re-rating. Disabled at K = 0.
- **`[Select needsWork]`** secondary appears only when the current
  selection differs from the default (handles "I cleared everything;
  put it back").

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

The "what's coming?" tab. Today answers "what now?"; Plan shows the
schedule across time + the new-word queue. **Single ScrollView**:
Roadmap + 7-Day Workload chart + tab bar + worklist all scroll
together. The user can scroll the chart out of the way and let the
worklist take the full viewport — the chart is a once-per-visit
preview, not a perpetual control, so pinning it at the top wastes
screen real estate when the worklist is the actual destination.

The worklist itself is **tab-segmented**:
`[Today][Tomorrow][This Week][Later][New]` with a colored count
chip per tab. One tab visible at a time so the user focuses on the
bucket they actually want, instead of disclosure-tree clicking.

### Layout

```
┌── Plan ────────────────────────────────────────────────────┐
│  Roadmap                                                    │
│  GRE Core 500 ━━━━━━━━━━━━●━━━━━━━━━━━━━ 234/500 (47%)     │
│  At 10 new/day, ETA ~27 days.                               │
│                                                             │
│  7-Day Workload                                             │
│   30 ┤                                                      │
│   20 ┤   ▆▆                                                 │
│   10 ┤▄▄ ▆▆ ▆▆ ▅▅ ▃▃ ▂▂ ▂▂                                  │
│      └─Mon Tue Wed Thu Fri Sat Sun                          │
│  ─────────────────────────────────────────────────────────  │
│  [Today · 18][Tomorrow · 24][This week · 92][Later · 145][New · 50] │
│  ─────────────────────────────────────────────────────────  │
│  ⚠  aberrant      adj 异常的           (overdue)             │
│     coalesce      v   联合                                   │
│     equivocate    v   含糊                                   │
│     ⋯ scrolls full-height                                    │
└─────────────────────────────────────────────────────────────┘
```

### Roadmap
- Progress bar against the active book; ETA in days at the daily new-word
  pace. Caveat surfaced about FSRS accuracy variance.

### 7-Day Workload
- Swift Charts `BarMark` of upcoming due-card load per day.
- Snapshot disclaimer below — every rating shifts future dates.

### Worklist tabs

| Tab | Contents | Tint |
|-----|----------|------|
| Today | `DueBucket.overdue + .today` merged. Overdue rows flagged inline with red marker. | orange |
| Tomorrow | `DueBucket.tomorrow` | yellow |
| This week | `DueBucket.thisWeek` (days 2..6) | green |
| Later | `DueBucket.later` (day 7+, capped 30) | gray |
| New | Next 50 words by book sortOrder (was the standalone "New Words Queue" section) | blue |

Each tab's count chip renders in its tint color; the active tab's chip
fills (white text on tint), inactive chips are gray. Empty states give
specific copy ("Tomorrow is open" / "Nothing scheduled for next week")
instead of one generic line.

### Note: "All Books" mode
- When no active book is selected, Roadmap hides itself; Workload + tab
  lists show global counts.

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

Library answers **one** question: "browse this app's words." Everything
else is a **slice** on that list — Book, Unit, State, Sort, Search are
peer filters; they don't open separate views. Practice (Flashcard /
Typing) is an **action** on the current slice via footer buttons, not
a parallel mode.

### Layout

Mail-style split when the window is wide enough (≥ 900pt), single-column
push navigation otherwise. Layout selection is automatic via `GeometryReader`.

```
┌── Library (wide) ───────────────────────────────────────────┐
│ [search] [Book ▾] [Unit ▾] [State ▾] [Sort ▾]               │
│ ─────────────────────────────────────────────────────────── │
│  aberrant     /æˈber.ənt/ adj 异常的    Review   │ aberrant │
│  coalesce     ...          v   联合     Learning │ /æˈber/  │
│  equivocate   ...          v   含糊其辞  Review  │ ━━━━━━  │
│  garrulous    ...          adj 啰嗦的   New      │ Learning │
│  ⋯                                                │ Progress │
│                                                  │ ⋯        │
│ Showing 13,422                                   │          │
└─────────────────────────────────────────────────────────────┘
```

When a Unit is picked, the header collapses to `[search] [Book] [Unit]`
(State + Sort are redundant inside a single unit) and the footer
becomes an action surface:

```
┌── Library · Unit 5 ─────────────────────────────────────────┐
│ [search] [Book ▾] [Unit: 5 (efflorescent — embellish) ▾]    │
│ ─────────────────────────────────────────────────────────── │
│  efflorescent  ...                       New                │
│  effrontery    ...                       New                │
│  effusive      ...                       Learning           │
│  ⋯                                                          │
│ ─────────────────────────────────────────────────────────── │
│ efflorescent — embellish    [▭ Flashcard]  [⌨ Typing]       │
│ ● 0 Mastered  ● 1 Review  ● 2 Learning  ● 9 New   12 words  │
└─────────────────────────────────────────────────────────────┘
```

### Filtering, Sorting, Search

All run as SQL — never as in-memory filtering of decoded `Word` blobs.
Backed by `WordSummary` projections; see `data.md`.

- **Search** (debounced 300ms): `LIKE` on `spelling` or first Chinese def.
- **Book filter** (defaults to active study book; two-way synced with
  `AppState.activeBookId` so Today / Plan / Library always agree on the
  current book): `INNER JOIN wordListEntry`.
- **Unit picker** (only when a Book is selected): "All units" or one of
  the book's `unitSize`-row slices, labeled with the slice's first and
  last spelling — "Unit 5 (efflorescent — embellish)". Backed by
  `DatabaseService.fetchUnitRanges(bookId:unitSize:)`. Selecting Unit ≠
  All hides the State + Sort pickers (the unit IS the slice; per-row
  state badges remain) and forces the SQL to `state: .all, sort:
  .bookOrder` so the unit's natural order is preserved. The Swift-side
  `sliceForUnit` then narrows the loaded set to the unit's
  `firstSpelling..lastSpelling` window — Search still cuts within that
  window if active.
- **State filter** (Book mode only): New / Learning / Review / Mature.
- **Sort** (Book mode only): Book Order (default when a book is
  selected — uses `wordListEntry.sortOrder`) / A→Z. Without a book
  picked, Book Order silently falls back to A→Z. Sort cases for
  `dueDate` and `lapses` were removed in erudite-31 — Plan's
  `[Today][Tomorrow]` tabs and Today's recap own those signals now.

### A-Z jump bar

Vertical 26-letter strip between the list pane and the resizable
divider, **mounted only when sort = .alphabetical** (was always-on
before; meaningless under Book Order, which is its default sort
when a book is selected). Click a letter → first matching row gets
selected; SwiftUI List auto-scrolls. Letters with zero matches
under current filters are dimmed.

### No pagination

Library reads the full matching slice in one SQL hit and lets
SwiftUI List recycle rows lazily. 13K rows render fine. The
prior "200 per page + Load More" model was removed in erudite-31
because pagination + jump-bar were two overlapping "position"
mental models — picking one path resolves the conflict.

### Footer

Two flavors:

- **Book mode** (no unit selected): thin status line "Showing N".
- **Unit mode** (unit selected): shows the unit's spelling range +
  `[▭ Flashcard]` `[⌨ Typing]` direct-start action buttons + a row
  of progress chips (Mastered / Review / Learning / New, derived
  from `summaries.cardState`). Pressing a button builds the unit
  via `StudyQueueBuilder.buildChapterUnit` and pins it to AppState
  via `startUnit(unit, in:)` — no UnitPreview detour, the user
  just saw the words in the list.

### Resizable split + persistent state

- Split layout uses **Mail-style proportions**: list defaults to 360pt
  (draggable 280–600pt via the divider's hit-region), detail fills the
  remainder. The list width is persisted to `UserDefaults` so it survives
  restarts.
- All Library "live state" (loaded summaries, selection, filter
  pickers, selected unit index, list pane width) lives in
  `LibraryState` (`@Observable`, owned by `AppState`). Switching tabs
  and coming back preserves position — the user doesn't snap back to
  "abacus" every time.
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
