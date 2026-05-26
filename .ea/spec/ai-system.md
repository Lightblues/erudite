# AI System Design

## Philosophy

AI is not a feature tab — it is a three-layer system woven into every interaction.

```
Layer 1: Micro (per-word)
Layer 2: Meso (per-session)
Layer 3: Macro (learning plan)
```

---

## 1. AI Teacher — Always-Present Assistant

### UI Presence

A persistent bar (bottom or side panel) visible on every screen:

```
┌─ AI Teacher Bar ──────────────────────────────────────────┐
│ 💡 contextual insight or suggestion                        │
│                                                            │
│ [Input: ask anything...]                    [Ask] [Explain]│
└────────────────────────────────────────────────────────────┘
```

### Interaction Modes

**Passive (user-triggered):**
- Tap any word → ask questions about it
- Free-form natural language input
- "Compare X and Y"
- "Give me a story to remember this word"
- "Why do I keep forgetting this?"

**Proactive (AI-triggered, non-intrusive):**
- Detects struggle → surfaces tip as a subtle bubble (dismissable)
- Session start → brief daily plan
- Session end → summary + tomorrow suggestion
- Detects confusion pair → offers disambiguation

### Context-Awareness

The AI Teacher has access to:

```swift
struct LearningContext {
    // Immediate
    let currentWord: Word?
    let currentMode: StudyMode
    let sessionWords: [Word]
    let recentRatings: [Rating]       // last few ratings in session

    // Short-term (today)
    let todayNewCount: Int
    let todayReviewCount: Int
    let todayAccuracy: Double
    let todayWeakWords: [Word]

    // Long-term (profile)
    let totalMastered: Int
    let weakCategories: [String]       // weak root families / clusters
    let confusionPairs: [(Word, Word)]
    let preferredMnemonicStyle: MnemonicStyle
    let studyStreak: Int
    let daysUntilExam: Int?
}
```

### Context-Aware Behavior Examples

| User Situation | Context Available | AI Response |
|---------------|-------------------|-------------|
| Viewing `aberrant` card | Current word + history (3rd time forgotten) | "Last time you confused this with abhorrent. Key difference: aberrant = deviating, abhorrent = detestable" |
| 3 consecutive "Again" ratings | Recent failure pattern | "These are all negative-sentiment words. Want me to create a story linking them?" |
| Browsing `bene-` root page | Current root + mastered related words | "You already know benevolent. Beneficent adds the idea of actively doing good" |
| Wrong answer in SE quiz | Error + selected wrong option | "You chose X — it does mean Y, but in this context the key nuance is..." |
| Opening app for today | Yesterday's stats + FSRS predictions | "4 of yesterday's 15 words are predicted to fade today. Let's review them first" |

---

## 2. Layer 1: Micro — Per-Word AI

### Personalized Mnemonics
- Generated on first encounter with a word
- Considers user's native language (Chinese) for phonetic/visual associations
- Can regenerate if user rates it unhelpful (👎)
- User can edit and save their own

### Word Root Analysis
- Automatic morpheme breakdown
- For words without clear etymological roots: AI provides creative associations
- Links to root family (other words sharing the same root)

### Synonym Disambiguation
- Triggered when reviewing words with overlapping meanings
- Explains precise distinctions (e.g., equivocate vs prevaricate vs tergiversate)
- Uses GRE-relevant context

### Example Sentence Generation
- GRE-style academic sentences
- Optionally: fun/memorable sentences for better encoding
- Source-tagged (AI-generated vs. from official materials)

---

## 3. Layer 2: Meso — Per-Session AI

### Session Start: Daily Briefing
```
"Good morning! Today's plan:
 - 12 due reviews (4 predicted difficult)
 - 8 new words recommended
 - Focus: yesterday's 'criticism' cluster had 40% accuracy
 - Estimated time: 25 minutes"
```

### Mid-Session: Pattern Detection
- Detects consecutive failures → offers alternative learning strategy
- Detects topic cluster in errors → suggests group study
- Monitors pacing (too fast = shallow encoding warning)

### Session End: Summary
```
"Session complete:
 - Learned 10 new words, reviewed 18
 - Accuracy: 78% (↑5% vs yesterday)
 - Strongest: Latin-root words
 - Weakest: 'speaking/communication' cluster
 - Tomorrow preview: 22 reviews due"
```

---

## 4. Layer 3: Macro — Learning Plan AI

### Weekly Plan Generation
- Based on: remaining words, current pace, retention rate, exam date
- Adjusts daily new word count dynamically
- Recommends mode shifts (e.g., "switch from flashcard to quiz for these words")

### Stage Transition Detection
```
"Your core-tier accuracy is now 92%.
 Recommendation: Start mixing in advanced-tier words.
 Also switching your review mode from flashcard to quiz for mature words."
```

### Exam Countdown Mode
```
"14 days until exam:
 - Stop new words
 - Focus on high-frequency error words
 - Prioritize SE pairing drills
 - Review 50 words/day in speed mode for maintenance"
```

### Adaptive Strategy
- Tracks which mnemonic styles work best for the user
- Learns optimal session length (when accuracy drops off)
- Identifies time-of-day effects on retention

---

## 5. AI Implementation Strategy

### API Choice
- Primary: Claude API (claude-sonnet for speed, claude-opus for complex analysis)
- Fallback: OpenAI GPT-4o
- Protocol-based abstraction for easy switching

### Cost Management
- **Batch pre-generation:** Mnemonics, root analysis, example sentences generated once at word-database build time → stored locally
- **On-demand generation:** Comparisons, quiz explanations, briefings → API call with caching
- **Local cache:** Once generated, all AI content persisted to SQLite — never regenerate the same content
- **Context compression:** Send minimal context to API (not full conversation history)

### Prompt Architecture

```
System Prompt (AI Teacher persona):
- Role: GRE vocabulary tutor, patient and insightful
- Style: Concise, uses analogies, connects to Chinese when helpful
- Constraints: Always accurate, admits uncertainty, GRE-focused

Per-request context injection:
- Current word data (definition, roots, synonyms)
- User's history with this word (times seen, times forgotten)
- Recent session context (last 5 words, ratings)
- User profile summary (weak areas, preferences)
```

### Offline Degradation
- Without network: use pre-cached AI content only
- Proactive features disabled
- Reactive queries show "offline" state with cached fallback
- Queue requests for when network returns
