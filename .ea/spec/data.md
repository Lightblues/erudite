# Data Design

## Word Database Strategy

Two-tier approach: **Bundled vocabulary** (pre-enriched for learning) + **Dynamic dictionary** (API-cached for reading)

```
┌─────────────── Architecture ───────────────────────────┐
│                                                         │
│  ┌─── Bundled (words.json, git-tracked) ────────────┐  │
│  │  13K words: GRE/TOEFL/SAT word books              │  │
│  │  Enriched: ECDICT (freq/tags) + AI (mnemonics)    │  │
│  │  Format: one-word-per-line JSON, ~6 MB            │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─── Dynamic Cache (SQLite, runtime) ──────────────┐  │
│  │  User clicks unknown word → API lookup → cache    │  │
│  │  Priority: MW Collegiate → Free Dictionary API    │  │
│  │  Grows over time based on user's reading          │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─── External (links) ─────────────────────────────┐  │
│  │  "Open in Eudic" / "Open in Merriam-Webster"     │  │
│  │  For full dictionary experience                    │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Build Pipeline (scripts/)

```
data/raw/                         (git-ignored, large source files)
├─ GRE_3.json (新东方, 6.5K)      ← Primary: richest fields
├─ GRE_2.json (有道, 7.2K)        ← Backup
├─ 再要你命3000.csv               ← Frequency signal
├─ MagooshFlashcard.csv           ← Frequency signal + examples
├─ qwerty-learner wordbooks       ← Book structure (6 books)
└─ ECDICT (770K, MIT)             ← Phonetics + frequency + tags

Pipeline steps (in order):
1. build_worddb.py      → words.json v2 (6.5K rich words from GRE_3)
2. build_multibook.py   → words.json v3 (13K merged) + wordbooks.json
3. enrich_ecdict.py     → Fill phonetics, BNC/COCA frequency, exam tags
4. enrich_ai.py         → AI batch: mnemonics, examples, synonyms/antonyms
5. merge_ai_enrichment.py → Merge AI results back into words.json

Output: Erudite/Erudite/Resources/Data/words.json (git-tracked, one-word-per-line)
```

### Enrichment Sources

| Source | Coverage | Fields Provided |
|--------|----------|-----------------|
| GRE_3 (新东方) | 6,515 core | CN defs, EN defs, examples, synonyms, phonetics, mnemonics |
| ECDICT (MIT) | 99% match | Phonetics (补全), BNC/COCA freq rank, Collins stars, exam tags |
| AI (gemini-flash) | Batch, incremental | Concise CN, mnemonics (word roots), examples, synonyms, antonyms |
| MW API (runtime) | On-demand | Authoritative EN defs, etymology, thesaurus |
| Free Dict API (runtime) | On-demand fallback | EN defs, IPA, synonyms |

### AI Enrichment Details

- **Model**: gemini-3.1-flash-lite (via OpenAI-compatible API)
- **Concurrency**: 10 parallel requests
- **Speed**: ~2.3 words/s, full 13K in ~95 min
- **Checkpoint**: Resumable (data/ai_enrichment_checkpoint.json)
- **Config**: .env file (ENRICH_API_URL, ENRICH_API_KEY, ENRICH_MODEL)
- **Quality focus**: Concise Chinese (≤10 chars), word-root mnemonics, natural examples

---

## Dynamic Dictionary (Runtime)

When user clicks an unknown word not in bundled DB:

```
WordLookupService.lookupAsync(word)
  ├─ [1] Local SQLite (bundled + cached) → instant
  ├─ [2] MW Collegiate API + Thesaurus → rich English + etymology
  ├─ [3] Free Dictionary API → fallback (no API key needed)
  └─ [4] "Not Found" popover → "Open in Eudic" link
```

- Results cached permanently to local SQLite DB
- Source tracked via tags: `source:mw`, `source:free_dict`
- Lower-quality cache auto-upgrades when better source available
- MW keys in Config.json (git-ignored); 1000 calls/day free tier

---

## Layer 1: Prebuilt Word Database
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
    case core = 1       // ~500
    case common = 2     // ~1800
    case advanced = 3   // ~10800
}
// NOTE: As of 2026-05 the Tier filter was removed from the Library UX —
// the bundled frequency split has no authoritative GRE provenance and was
// noisy as a priority signal (~83% in advanced). The model field is kept
// for backward compat; UI surfaces only `Book` + `State` for now.
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

-- User-generated content (mnemonics, notes, future categories).
-- Single table keyed by `type` so new content kinds ship without migration.
CREATE TABLE user_content (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wordId TEXT NOT NULL REFERENCES word(id) ON DELETE CASCADE,
    type TEXT NOT NULL,                 -- 'mnemonic' | 'note' | future
    content TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
);

CREATE INDEX idx_user_content_word ON user_content(wordId, type);
```

---

## WordSummary Projection (list views)

`Word` is a fat model: definitions, examples, synonyms, roots, mnemonics,
tags. Library / Today / Plan all show *list rows* that need only a few
fields each. Decoding 13K full `Word` JSON blobs to render a list is
wasteful (and was the source of Library lag pre-erudite-24).

So list views read a lightweight `WordSummary` instead, populated directly
from SQL via `json_extract()`:

```swift
struct WordSummary: Identifiable, Hashable {
    let id: String              // wordId
    let spelling: String
    let phonetic: String?
    let frequency: FrequencyTier
    let firstDefZh: String?     // json_extract(...definitions[0].chinese)
    let posLabel: String?       // json_extract(...definitions[0].partOfSpeech)
    let hasMnemonic: Bool       // json_array_length(mnemonics) > 0
    let cardState: CardState?   // LEFT JOIN reviewCard
    let dueDate: Date?          // populated by queries that need it
}
```

The "data path forks" by design:

- **List paths** (Library, Today preview, Plan queue/backlog) read
  `[WordSummary]` from SQL. Filtering, sorting, pagination, and search all
  run in the database.
- **Detail paths** (`WordDetailView`) read the full `Word` via
  `fetchWord(id:)` only when the user opens a row.

This is what makes Library responsive at 13K words; the cost is a small
amount of duplicated query code (one for summaries, one for full).

### Key DB methods

| Purpose | Method |
|---------|--------|
| Library / generic list | `fetchWordSummaries(book, state, search, sort, limit, offset)` + `fetchWordSummaryCount(...)` |
| Today: due preview | `fetchDueSummaries(now, inBook, limit)` |
| Today / Plan: new queue | `fetchNewWordSummaries(inBook, limit)` |
| Plan: workload chart | `fetchDueCountsByDay(daysAhead, inBook)` → `[(Date, Int)]` |
| Plan: backlog groups | `fetchDueBacklog(inBook, perBucketLimit)` and `fetchDueBacklogCounts(...)` over `DueBucket` (overdue/today/tomorrow/thisWeek/later) |
| WordDetail: card + history | `fetchReviewCard(forWord:)`, `fetchReviewLogs(cardId:limit:)`, `fetchBooks(containingWord:)` |
| User content (mnemonics today, notes next) | `addUserContent`, `updateUserContent`, `deleteUserContent`, `fetchUserContent(wordId, type?)` |
| Schema/data versioning | `metaValue(forKey:)`, `setMetaValue(_:forKey:)`, `upsertWordData(_:)` |
| Library jump bar | `offsetForFirstSpelling(startingWith:book:state:search:)`, `availableStartingLetters(book:state:search:)` |
| DB integrity audit | `checkIntegrity()` returning `IntegrityReport` (orphan rows, missing fields, untagged words) — driven by `Views/Debug/DataDiagnosticsView` |

> Read-row gotcha: SQLite returns integers as `Int64`. `row["x"] as? Int`
> goes through `DatabaseValue` and silently returns `nil` for live `Int64`
> values — use the typed-annotation form `let x: Int? = row["x"]` instead
> (lessons.md "row[\"key\"] as? Int is a trap"). Prior to 2026-05 the
> `cardState` column was being read with the broken form, so the State
> filter looked correct but every row's badge fell back to "New".

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


---

## Data Versioning and Upgrade

`words.json` ships a `version` field. The DB tracks the last-applied
version under `meta(key='wordsVersion')`. On every app launch,
`WordLoader.seedDatabaseIfNeeded()` picks one of three paths:

1. **Fresh install** (`word` table empty) → INSERT all words, create
   FSRS `reviewCard` rows for each, seed `wordList` + `wordListEntry`,
   stamp `wordsVersion`.
2. **Upgrade** (DB version ≠ bundle version) → `upsertWordData([Word])`
   runs an UPDATE for each existing word's `data` BLOB and an INSERT for
   any new words. **It must NOT use `INSERT OR REPLACE`**: SQLite
   implements REPLACE as DELETE-then-INSERT, and `reviewCard.wordId` has
   `ON DELETE CASCADE` — a naive REPLACE would wipe every user's FSRS
   progress. UPDATE on the same primary key avoids the DELETE entirely,
   so `reviewCard` / `reviewLog` / `user_content` are untouched.
3. **Up to date** → fast path, no work.

This is what lets ai-enrichment of `words.json` (mnemonics, examples,
synonyms, etc.) ship as a regular bundle update without resetting any
user's review progress.

### Diagnostics

`Views/Debug/DataDiagnosticsView` (Debug Panel ⌘⇧D → Data tab) computes
a read-only diff between `words.json` and the live DB:

- Bundle vs DB version + word count delta
- Word-set delta (bundle-only / DB-only — DB-only words come from
  `WordLookupService` cache hits)
- Per-field upgrade counts (how many words gain `mnemonic`, `chinese
  def`, `examples`, etc. on the next upgrade)

Useful for sanity-checking what an upcoming `words.json` bump will do
before deciding to ship it.

### Indexes

- `idx_word_spelling` on `word(spelling COLLATE NOCASE)` — A→Z sort
  becomes index-only.
- `idx_wle_list_order` on `wordListEntry(listId, sortOrder)` — book-order
  pagination is a 2-step index lookup, not a sort.
