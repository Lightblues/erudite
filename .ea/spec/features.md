# Feature Design

## 1. Today / Home

The entry point when opening the app.

### AI Daily Briefing
- Summarizes yesterday's progress
- States today's plan (N words to review + M new words, estimated time)
- Highlights focus areas ("yesterday's 'criticism' word group had low accuracy")
- Quick stats: streak days, mastered count, projected completion date

### Quick Actions
- [Start Learning] → FSRS flashcard session (mixed new + due)
- [Review Due] → Due cards only
- [Type Practice] → Typing tab (qwerty-learner style)

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

**Architecture:** Separate tab (not nested in Flashcard), independent from FSRS scheduling.

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
| Esc | Pause (→ idle) or exit |
| Return | Advance (after word complete) |

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

### Word List Management
- Predefined tiers: Core (500) / Common (1000) / Advanced (1500+)
- Custom groups (user-created)
- Smart groups: "This week's mistakes", "Confusion pairs", "Low retention"
- Import: Anki .apkg, CSV/TSV, plain text word list
- Export: Anki-compatible, CSV

### Word Root Explorer
- Visual morpheme tree: select a root → see all derived words
- Root-based study sessions ("learn all bene- words together")
- Construction analysis: prefix + root + suffix breakdown
- Interactive: tap any segment to see other words sharing it

### Word Detail View
- All definitions (English + Chinese)
- Root breakdown
- Example sentences (with source tags)
- Synonym/antonym groups
- Sentiment label
- User's personal mnemonics (editable)
- FSRS stats for this word (next due, stability, lapses)
- AI-generated content (expandable)

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
