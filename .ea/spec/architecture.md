# Technical Architecture

## Stack

- **Language:** Swift 5.0 (with Swift 6 concurrency features enabled)
- **UI Framework:** SwiftUI
- **Minimum OS:** macOS 26.5
- **IDE:** Xcode 26.5+
- **Project Type:** Xcode native (.xcodeproj with PBXFileSystemSynchronizedRootGroup)
- **Architecture Pattern:** MVVM + Repository
- **Storage:** SQLite via GRDB.swift
- **AI:** Claude API (primary), OpenAI (fallback)

---

## Project Structure

```
Erudite/
├── Erudite.xcodeproj
├── Erudite/
│   ├── App/
│   │   ├── EruditeApp.swift            # @main entry
│   │   └── AppState.swift              # Global state
│   ├── Models/
│   │   ├── Word.swift                  # Word data model
│   │   ├── WordRoot.swift              # Morpheme/root model
│   │   ├── ReviewCard.swift            # FSRS card state
│   │   ├── ReviewLog.swift             # Review history entry
│   │   ├── StudySession.swift          # Session tracking
│   │   └── WordList.swift              # Word list/group
│   ├── Engine/
│   │   ├── FSRS/
│   │   │   ├── FSRSEngine.swift        # Core scheduling algorithm
│   │   │   ├── FSRSParameters.swift    # Algorithm parameters (19 trainable)
│   │   │   └── FSRSModels.swift        # Card state transitions
│   │   ├── Scheduler.swift             # Daily plan generation
│   │   └── StatisticsEngine.swift      # Aggregation and analysis
│   ├── Services/
│   │   ├── DatabaseService.swift       # GRDB wrapper
│   │   ├── AIService.swift             # LLM API abstraction
│   │   ├── AIProviders/
│   │   │   ├── AIProvider.swift        # Protocol
│   │   │   ├── ClaudeProvider.swift    # Anthropic API
│   │   │   └── OpenAIProvider.swift    # Fallback
│   │   ├── ImportService.swift         # Anki/CSV/text import
│   │   └── ExportService.swift         # Data export
│   ├── ViewModels/
│   │   ├── StudyViewModel.swift        # FSRS study session logic
│   │   ├── ReviewViewModel.swift       # Flashcard/quiz/speed logic
│   │   ├── DashboardViewModel.swift    # Stats aggregation
│   │   ├── LibraryViewModel.swift      # Word list management
│   │   └── AITeacherViewModel.swift    # AI context + interaction
│   ├── Views/
│   │   ├── Main/
│   │   │   ├── ContentView.swift       # Navigation structure
│   │   │   └── TodayView.swift         # Home / daily briefing
│   │   ├── Study/
│   │   │   ├── StudyView.swift         # FSRS card session
│   │   │   ├── CardFrontView.swift     # Card front face
│   │   │   ├── CardBackView.swift      # Card back face
│   │   │   └── RatingButtons.swift     # Again/Hard/Good/Easy
│   │   ├── Review/
│   │   │   ├── FlashcardView.swift     # Binary know/don't-know
│   │   │   ├── QuizView.swift          # Multiple choice quiz
│   │   │   ├── SEQuizView.swift        # SE synonym pairing
│   │   │   └── SpeedReviewView.swift   # Auto-advance speed mode
│   │   ├── Library/
│   │   │   ├── WordListBrowser.swift   # Browse word lists
│   │   │   ├── WordDetailView.swift    # Single word full detail
│   │   │   ├── RootExplorerView.swift  # Word root tree visualization
│   │   │   └── ImportView.swift        # Import wizard
│   │   ├── Dashboard/
│   │   │   ├── DashboardView.swift     # Stats overview
│   │   │   ├── RetentionChart.swift    # Retention curve
│   │   │   ├── HeatmapView.swift       # Streak heatmap
│   │   │   └── WeaknessView.swift      # Weak areas analysis
│   │   └── AI/
│   │       ├── AITeacherBar.swift      # Persistent AI bar (global)
│   │       └── AIConversationView.swift # Expanded AI interaction
│   └── Resources/
│       ├── Data/
│       │   ├── words.json              # Prebuilt word database
│       │   └── roots.json              # Root/morpheme reference
│       └── Assets.xcassets
├── EruditeTests/
│   ├── FSRSEngineTests.swift
│   ├── SchedulerTests.swift
│   └── StatisticsEngineTests.swift
└── Package.swift                        # SPM dependencies
```

---

## Architecture Pattern

```
MVVM + Repository

┌──────────┐     ┌──────────────┐     ┌─────────────┐
│   View   │ ←→  │  ViewModel   │ ←→  │  Repository │
│ (SwiftUI)│     │ (@Observable)│     │  (Protocol) │
└──────────┘     └──────────────┘     └──────┬──────┘
                                              │
                              ┌────────────────┼────────────────┐
                              │                │                │
                     ┌────────▼───┐   ┌───────▼──────┐  ┌─────▼─────┐
                     │ Database   │   │  AI Service  │  │ FSRS      │
                     │ (GRDB)     │   │  (Claude)    │  │ Engine    │
                     └────────────┘   └──────────────┘  └───────────┘
```

### Key Design Decisions

- **@Observable** (Swift 5.9+) over ObservableObject — cleaner, better performance
- **Repository protocol** — isolates data access, enables testing with mocks
- **FSRS Engine is pure logic** — no IO, no UI, 100% unit-testable
- **AI Service is protocol-based** — swap providers without touching UI/logic

---

## FSRS Algorithm

### Overview

FSRS (Free Spaced Repetition Scheduler) is the state-of-the-art open-source SRS algorithm. It uses 19 trainable parameters to model memory stability and difficulty.

### Core Concepts

| Concept | Description |
|---------|-------------|
| Stability (S) | How many days until the probability of recall drops to 90% |
| Difficulty (D) | Inherent difficulty of the item [1, 10] |
| Retrievability (R) | Current probability of successful recall |
| State | new → learning → review → relearning |

### Key Formulas

```
Retrievability:
  R(t) = (1 + t / (9 * S))^(-1)
  where t = elapsed days since last review

After successful recall (rating ≥ hard):
  S' = S * (1 + e^(w8) * (11 - D) * S^(-w9) * (e^(w10 * (1-R)) - 1))

After forgetting (rating = again):
  S' = w11 * D^(-w12) * ((S+1)^w13 - 1) * e^(w14 * (1-R))

Difficulty update:
  D' = D + w6 * (rating - 3)  (clamped to [1, 10])
```

### Parameters

19 parameters (w0-w18), with sensible defaults from FSRS-5. Can be personalized by training on user's review history.

### Reference Implementation

- [open-spaced-repetition/fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs) (Rust, canonical)
- [open-spaced-repetition/swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs) (Swift port)
- Consider: self-implement for full understanding and customization

---

## Dependencies

| Purpose | Library | Notes |
|---------|---------|-------|
| Database | [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite wrapper, type-safe, Combine/async support |
| Charts | Swift Charts (system) | macOS 14+, Apple first-party |
| Networking | URLSession (system) | AI API calls, no third-party needed |
| JSON | Codable (system) | Word data parsing |
| Markdown | [swift-markdown](https://github.com/apple/swift-markdown) | Render AI responses |
| Audio | AVFoundation (system) | Word pronunciation playback |
| FSRS | Self-implemented | Core algorithm, recommend understanding fully |

**Principle: Minimal external dependencies. Maximize Apple-native frameworks.**

---

## AI Service Architecture

```swift
// Provider abstraction
protocol AIProvider {
    func generate(prompt: String, system: String?) async throws -> String
    func generateStream(prompt: String, system: String?) -> AsyncThrowingStream<String, Error>
}

// High-level AI capabilities
class AIService {
    private let provider: AIProvider
    private let cache: AICacheRepository

    // Per-word
    func generateMnemonic(word: Word) async throws -> String
    func generateExample(word: Word) async throws -> String
    func compareWords(_ a: Word, _ b: Word) async throws -> String
    func explainWord(word: Word, question: String) async throws -> String

    // Per-session
    func generateDailyBriefing(context: LearningContext) async throws -> String
    func generateSessionSummary(session: StudySession, context: LearningContext) async throws -> String

    // Per-plan
    func generateWeeklyPlan(context: LearningContext) async throws -> StudyPlan
    func generateWeeklyReport(stats: WeeklyStats) async throws -> String

    // Quiz generation
    func generateDistractors(word: Word, count: Int) async throws -> [String]
    func explainQuizAnswer(question: QuizQuestion, userAnswer: String) async throws -> String
}
```

### Cost Control Strategy

| Content Type | When Generated | API Calls |
|-------------|----------------|-----------|
| Mnemonics, root analysis, examples | Build time (batch) | Once per word, bundled in app |
| Daily briefing | Session start | 1 per day |
| Session summary | Session end | 1 per session |
| Word comparison | On user request | On demand, cached |
| Quiz explanation | On wrong answer | On demand, cached |
| Weekly report | Weekly | 1 per week |

Estimated daily API cost: minimal (mostly cached pre-generated content).

---

## Storage Architecture

```
~/Library/Application Support/Erudite/
├── erudite.db                  # SQLite database (GRDB)
├── ai_cache/                   # Overflow AI content if needed
└── exports/                    # User export temp files

App Bundle:
├── Resources/Data/words.json   # Prebuilt word database
└── Resources/Data/roots.json   # Root reference data
```

### Data Flow

```
App Launch:
  1. Check if erudite.db exists
  2. If first launch: import words.json → SQLite
  3. Create ReviewCard for each word (state = new)
  4. Load user preferences, FSRS parameters

Study Session:
  1. Scheduler queries due cards (due_date ≤ now, ordered by priority)
  2. Mixes in new cards up to daily limit
  3. User rates each card → FSRSEngine computes next state
  4. Updated card + ReviewLog written to DB
  5. Session stats aggregated on completion

AI Interaction:
  1. Build LearningContext from current state
  2. Check ai_cache for existing content
  3. If miss: call AIService → cache result
  4. Return to UI (streaming for long responses)
```

---

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| FSRS Engine | Scheduling correctness, edge cases | Unit tests with known inputs/outputs |
| Scheduler | Daily plan generation, priority ordering | Unit tests |
| Statistics | Aggregation accuracy | Unit tests with fixture data |
| Database | CRUD operations, migrations | Integration tests with in-memory DB |
| AI Service | Prompt formatting, response parsing | Unit tests with mocked provider |
| ViewModels | State transitions, user interactions | Unit tests |

---

## Performance Considerations

- **SQLite indexes** on due_date and timestamp for fast queries
- **Lazy loading** word detail (full JSON only loaded on demand)
- **Background AI calls** — never block UI for API responses
- **Batch operations** — bulk card updates at session end, not per-rating
- **Memory** — word list browsing uses pagination, not load-all
