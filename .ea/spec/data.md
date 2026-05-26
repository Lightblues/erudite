# Data Design

## Word Database Strategy

Hybrid approach: Prebuilt base + User import + AI augmentation

```
┌─────────────── Data Pipeline ───────────────────────┐
│                                                      │
│  ┌──────────┐    ┌────────────┐    ┌─────────────┐  │
│  │ Base list │ +  │ AI enrich  │ →  │ Prebuilt DB │  │
│  │ (skeleton)│    │ (one-time) │    │ words.json  │  │
│  └──────────┘    └────────────┘    └──────┬──────┘  │
│                                           │         │
│  ┌──────────┐                    ┌────────▼───────┐ │
│  │ User     │ ──────────────────→│  Runtime DB    │ │
│  │ import   │                    │  (SQLite)      │ │
│  └──────────┘                    └────────┬───────┘ │
│                                           │         │
│  ┌──────────────────┐            ┌────────▼───────┐ │
│  │ AI real-time     │ ──────────→│  User layer    │ │
│  │ augmentation     │            │  (personalized)│ │
│  └──────────────────┘            └────────────────┘ │
└──────────────────────────────────────────────────────┘
```

---

## Layer 1: Prebuilt Word Database

### Source Word Lists

| Source | Size | Use |
|--------|------|-----|
| Magoosh GRE Vocabulary | ~1000 | Core + Common tiers |
| Gregmat Word List | ~1000 | Cross-reference, fill gaps |
| Barron's 333 High-Frequency | 333 | Validate core tier selection |
| 再要你命 3000 | ~3000 | Advanced tier supplement, Chinese definitions reference |

**Target:** ~1500-2000 deduplicated words, split into:
- Core (500): Must-know, highest frequency
- Common (1000): Should-know, covers most TC/SE
- Advanced (500+): Nice-to-have, diminishing returns

### Build Pipeline

```
Step 1: Skeleton (word list only)
  - Merge sources, deduplicate
  - Assign frequency tier based on occurrence across lists
  - Output: [spelling, frequency_tier]

Step 2: Base definitions (reliable sources)
  - Wiktionary (CC license, free to use)
  - WordNet (Princeton, open source)
  - Chinese definitions from public GRE prep materials
  - Output: + [definitions, part_of_speech, phonetic]

Step 3: AI enrichment (batch, one-time)
  For each word, generate:
  - Morpheme breakdown (prefix + root + suffix + logic)
  - Synonym groups (GRE SE-style pairs)
  - Sentiment classification (positive/negative/neutral)
  - GRE-style example sentence
  - Default mnemonic (connecting to Chinese/English associations)
  
  Quality control: Human spot-check 10-20% of output
  
Step 4: Package as words.json (bundled with app)
```

### Note on Official Materials

ETS does not publish an official GRE word list. All word lists are third-party compilations from real exam recall. The app should note this and allow users to add/modify words.

---

## Layer 2: User Import

### Supported Formats

| Format | Description |
|--------|-------------|
| Anki .apkg | Parse SQLite + media files from Anki export |
| CSV / TSV | Flexible column mapping (user assigns which column is what) |
| Plain text | One word per line → AI auto-fills remaining fields |

### Import Behavior
- Deduplicate against existing database
- Missing fields marked → background AI async fill
- User chooses: merge into existing list OR create new word list
- Imported words get a user-defined tag for filtering

---

## Layer 3: AI Real-Time Augmentation

### Triggers
- User imports plain word list → auto-complete missing fields
- User taps "Explain more" on any word → generate deep content
- User marks AI content as unhelpful (👎) → regenerate
- User adds custom mnemonic → AI can polish if requested

### Caching
- Generated once → persisted to SQLite → never regenerated
- User can rate AI content (👍/👎) to improve quality signal
- Regeneration only on explicit user request

---

## Data Models

### Word (Core Entity)

```swift
struct Word: Identifiable, Codable {
    let id: String                      // unique key (e.g., "abate")
    let spelling: String
    let phonetic: String?               // IPA
    let definitions: [Definition]
    let roots: MorphemeBreakdown?       // prefix + root + suffix analysis
    let synonymGroups: [[String]]       // grouped for SE practice
    let antonyms: [String]
    let sentiment: Sentiment            // positive / negative / neutral
    let frequency: FrequencyTier        // core / common / advanced
    let examples: [Example]
    let mnemonics: [String]             // default + user-added
    let tags: [String]
}

struct Definition: Codable {
    let partOfSpeech: PartOfSpeech      // noun / verb / adj / adv
    let english: String
    let chinese: String
}

struct MorphemeBreakdown: Codable {
    let segments: [Morpheme]            // ordered parts
    let logic: String                   // construction explanation
}

struct Morpheme: Codable {
    let text: String                    // e.g., "ab-"
    let type: MorphemeType              // prefix / root / suffix
    let meaning: String                 // e.g., "away from"
}

struct Example: Codable {
    let sentence: String
    let source: ExampleSource           // officialGuide / powerPrep / generated / custom
}

enum Sentiment: String, Codable {
    case positive, negative, neutral, ambivalent
}

enum FrequencyTier: Int, Codable, Comparable {
    case core = 1       // ~500, must master
    case common = 2     // ~1000, should master
    case advanced = 3   // 1500+, nice to have
}
```

### ReviewCard (FSRS State)

```swift
struct ReviewCard: Identifiable, Codable {
    let id: UUID
    let wordId: String

    // FSRS parameters
    var stability: Double               // memory stability (days)
    var difficulty: Double              // difficulty [1, 10]
    var elapsedDays: Int
    var scheduledDays: Int
    var reps: Int                       // total review count
    var lapses: Int                     // forgotten count
    var state: CardState                // new / learning / review / relearning
    var dueDate: Date
    var lastReview: Date?
}

enum CardState: Int, Codable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}
```

### ReviewLog (History)

```swift
struct ReviewLog: Codable {
    let id: Int                         // auto-increment
    let cardId: UUID
    let rating: Rating                  // again / hard / good / easy
    let state: CardState                // state at time of review
    let timestamp: Date
    let elapsedDays: Int
    let scheduledDays: Int
    let reviewDuration: TimeInterval?   // thinking time (optional tracking)
}

enum Rating: Int, Codable {
    case again = 1, hard = 2, good = 3, easy = 4
}
```

### StudySession

```swift
struct StudySession: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let mode: StudyMode
    let wordsStudied: Int
    let wordsNew: Int
    let wordsReviewed: Int
    let accuracy: Double                // % of good/easy ratings
    let aiSummary: String?              // AI-generated session summary
}

enum StudyMode: String, Codable {
    case fsrsLearn
    case flashcard
    case quizWordToDef
    case quizDefToWord
    case quizSEPairing
    case speedReview
}
```

---

## Database Schema (SQLite / GRDB)

```sql
-- Word data (content)
CREATE TABLE word (
    id TEXT PRIMARY KEY,
    spelling TEXT NOT NULL,
    phonetic TEXT,
    sentiment TEXT NOT NULL,
    frequency INTEGER NOT NULL,
    data BLOB NOT NULL                  -- JSON-encoded full Word struct
);

CREATE INDEX idx_word_frequency ON word(frequency);
CREATE INDEX idx_word_sentiment ON word(sentiment);

-- FSRS card state
CREATE TABLE review_card (
    id TEXT PRIMARY KEY,                -- UUID
    word_id TEXT NOT NULL REFERENCES word(id) ON DELETE CASCADE,
    stability REAL NOT NULL,
    difficulty REAL NOT NULL,
    state INTEGER NOT NULL,
    due_date TEXT NOT NULL,             -- ISO8601
    reps INTEGER NOT NULL DEFAULT 0,
    lapses INTEGER NOT NULL DEFAULT 0,
    elapsed_days INTEGER NOT NULL DEFAULT 0,
    scheduled_days INTEGER NOT NULL DEFAULT 0,
    last_review TEXT                    -- ISO8601
);

CREATE INDEX idx_card_due ON review_card(due_date, state);
CREATE INDEX idx_card_word ON review_card(word_id);

-- Review history (for stats + FSRS parameter optimization)
CREATE TABLE review_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id TEXT NOT NULL REFERENCES review_card(id),
    rating INTEGER NOT NULL,
    state INTEGER NOT NULL,
    timestamp TEXT NOT NULL,            -- ISO8601
    elapsed_days INTEGER NOT NULL,
    scheduled_days INTEGER NOT NULL,
    review_duration REAL               -- seconds
);

CREATE INDEX idx_log_time ON review_log(timestamp);
CREATE INDEX idx_log_card ON review_log(card_id);

-- Study sessions
CREATE TABLE study_session (
    id TEXT PRIMARY KEY,                -- UUID
    start_time TEXT NOT NULL,
    end_time TEXT,
    mode TEXT NOT NULL,
    words_studied INTEGER NOT NULL DEFAULT 0,
    words_new INTEGER NOT NULL DEFAULT 0,
    words_reviewed INTEGER NOT NULL DEFAULT 0,
    accuracy REAL,
    ai_summary TEXT
);

-- Word lists / groups
CREATE TABLE word_list (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    is_builtin INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
);

CREATE TABLE word_list_entry (
    list_id TEXT NOT NULL REFERENCES word_list(id) ON DELETE CASCADE,
    word_id TEXT NOT NULL REFERENCES word(id) ON DELETE CASCADE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (list_id, word_id)
);

-- User-generated AI content cache
CREATE TABLE ai_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    word_id TEXT NOT NULL REFERENCES word(id),
    content_type TEXT NOT NULL,         -- mnemonic / example / explanation / comparison
    content TEXT NOT NULL,
    rating INTEGER,                     -- user rating: 1=bad, 2=ok, 3=good
    created_at TEXT NOT NULL
);

CREATE INDEX idx_ai_cache_word ON ai_cache(word_id, content_type);
```

---

## Prebuilt Data Format (words.json)

```json
{
  "version": "1.0",
  "generated_at": "2026-05-26",
  "word_count": 1500,
  "words": [
    {
      "id": "aberrant",
      "spelling": "aberrant",
      "phonetic": "/æˈber.ənt/",
      "frequency": 1,
      "sentiment": "negative",
      "definitions": [
        {"pos": "adj", "en": "departing from the expected or normal", "zh": "异常的；偏离正道的"}
      ],
      "roots": {
        "segments": [
          {"text": "ab-", "type": "prefix", "meaning": "away from"},
          {"text": "err", "type": "root", "meaning": "to wander"},
          {"text": "-ant", "type": "suffix", "meaning": "adjective-forming"}
        ],
        "logic": "wandering away from the norm → deviating from expected"
      },
      "synonyms": [["anomalous", "atypical", "deviant"]],
      "antonyms": ["normal", "typical", "orthodox"],
      "examples": [
        {"text": "The aberrant results prompted researchers to redo the entire experiment.", "source": "generated"}
      ],
      "mnemonics": ["ab(离开) + err(犯错/走偏) → 走偏了 → 异常的"]
    }
  ]
}
```
