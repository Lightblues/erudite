# AI Companion Design

## Overview

Erudite AI Companion is an **always-present, context-aware learning assistant** implemented as a tool-augmented agent. It combines proactive micro-interventions with a full conversational interface.

Design philosophy: **AI as a study partner, not a feature button.** It remembers your journey, notices your patterns, and speaks up when it has something genuinely useful to say.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Erudite AI Companion                         │
│                                                                   │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────────┐  │
│  │ Agent Runtime │  │ Memory Store  │  │  Proactive Engine    │  │
│  │ (Chat Loop)   │  │ (Observations │  │  (Event → Tip)       │  │
│  │               │  │  + Profile)   │  │                      │  │
│  └──────┬────────┘  └──────┬────────┘  └──────────┬───────────┘  │
│         │                   │                      │              │
│         └───────────────────┼──────────────────────┘              │
│                             │                                     │
│                    ┌────────▼─────────┐                           │
│                    │  Context Builder  │                           │
│                    │  (System Prompt + │                           │
│                    │   Tool Results +  │                           │
│                    │   Memory)         │                           │
│                    └────────┬─────────┘                           │
│                             │                                     │
│              ┌──────────────┼──────────────┐                     │
│              │              │              │                      │
│     ┌────────▼───┐  ┌──────▼─────┐  ┌────▼──────┐              │
│     │ Tool Exec  │  │ LLM Backend│  │ Tip Cache │              │
│     │ (DB/FSRS/  │  │ (Claude    │  │ (Pre-gen  │              │
│     │  Stats)    │  │  Haiku/    │  │  content) │              │
│     └────────────┘  │  Sonnet)   │  └───────────┘              │
│                      └────────────┘                              │
└─────────────────────────────────────────────────────────────────┘
```

### Relationship to Coding Agents

| Concept | Claude Code | Erudite AI Companion |
|---------|-------------|---------------------|
| Agent loop | message → LLM → tool_use → execute → loop | Same |
| System prompt | CLAUDE.md + file context | Persona + user profile + mode context |
| Tools | Bash, Read, Write, LSP | DB queries, FSRS state, word operations |
| Memory | CLAUDE.md (static) + git | SQLite observations + compressed profile |
| Streaming | Terminal output | SwiftUI Text with typewriter |
| Proactive | None (purely reactive) | Event-driven tip engine |
| Cost model | Per-session, unlimited | Per-day budget, heavy caching |

Key difference: **Erudite AI must be latency-sensitive and cost-efficient.** A coding agent can take 5 seconds to respond; a flashcard tip must appear in <500ms (use cache) or be clearly async.

---

## UI: Fixed Right Panel

```
┌─────────────────────────────────────┬──────────────────────────┐
│                                     │  🤖 AI Companion         │
│                                     │  ─────────────────────── │
│   [Main Content Area]               │                          │
│                                     │  💡 Contextual tip here  │
│   - Flashcard / Typing / Quiz       │     (auto-updates with   │
│   - Dashboard / Library             │      current word/mode)  │
│                                     │                          │
│                                     │  ─── Chat ────────────── │
│                                     │  You: Why do I keep...   │
│                                     │  AI: Based on your       │
│                                     │      history, you tend   │
│                                     │      to confuse...       │
│                                     │                          │
│                                     │  ┌────────────────────┐  │
│                                     │  │ Ask anything...    │  │
│                                     │  └────────────────────┘  │
├─────────────────────────────────────┴──────────────────────────┤
│ [Study]  [Typing]  [Library]  [Dashboard]                      │
└────────────────────────────────────────────────────────────────┘
```

### Panel States

| State | Behavior |
|-------|----------|
| **Collapsed** | Only tip bar visible (1 line), click to expand |
| **Expanded** | Full panel: tip zone + chat history + input |
| **Hidden** | User can toggle off entirely (⌘.) |

### Panel Width
- Default: 280pt (narrow, doesn't crowd flashcard)
- Resizable: 240pt–400pt
- Keyboard: ⌘. to toggle, ⌘⇧. to focus input

### Tip Zone vs Chat Zone

The panel has two distinct areas:

1. **Tip Zone (top):** Proactive, ephemeral. Shows AI-generated contextual hints.
   - Updates automatically when word/mode changes
   - Dismissable (click × or auto-fade after 10s if not interacted)
   - No user input required

2. **Chat Zone (bottom):** Reactive, persistent. Full conversation interface.
   - User types questions, gets multi-turn responses
   - Scrollable history (within session; previous sessions summarized)
   - Supports tool use (AI can query your data, explain things)

---

## Agent Runtime

### Core Loop

```swift
@Observable
final class AICompanionRuntime {
    // Published state
    var messages: [CompanionMessage] = []
    var isGenerating = false
    var currentTip: TipContent?
    var streamingText: String = ""
    
    // Dependencies
    private let provider: AIProvider           // Claude API
    private let tools: ToolRegistry            // Available tools
    private let memory: MemoryStore            // Observations + profile
    private let contextBuilder: ContextBuilder // System prompt assembly
    
    // Core agent loop
    func send(_ userMessage: String) async {
        messages.append(.user(userMessage))
        isGenerating = true
        defer { isGenerating = false }
        
        let system = await contextBuilder.build(
            mode: AppState.shared.currentMode,
            memory: memory,
            currentWord: AppState.shared.currentWord
        )
        
        // Agent loop: keep going until text response (no more tool calls)
        var turnMessages = messages.map(\.toLLMMessage)
        
        while true {
            let response = try await provider.generateWithTools(
                messages: turnMessages,
                system: system,
                tools: tools.schemas
            )
            
            switch response.stopReason {
            case .text:
                // Final text response → stream to UI
                messages.append(.assistant(response.text))
                break  // Exit loop
                
            case .toolUse:
                // Execute tools, append results, loop back
                let toolResults = await tools.execute(response.toolCalls)
                turnMessages.append(.assistant(response.raw))
                turnMessages.append(.toolResults(toolResults))
                // Continue loop → LLM sees tool results
            }
        }
        
        // Post-turn: async memory extraction (don't block UI)
        Task.detached { [messages, memory] in
            await memory.extractObservations(from: messages)
        }
    }
}
```

### Message Types

```swift
enum CompanionMessage: Identifiable {
    case user(String)
    case assistant(String)
    case tip(TipContent)           // Proactive (not from user input)
    case toolActivity(ToolCall)    // Shown as "looking up your stats..."
    
    var id: UUID
    var timestamp: Date
}
```

### AIProvider Extension (for tool use)

The existing `AIProvider` protocol needs extension for the agent loop:

```swift
protocol AIProvider {
    // Existing
    func generate(prompt: String, system: String?) async throws -> String
    func generateStream(prompt: String, system: String?) -> AsyncThrowingStream<String, Error>
    
    // New: tool-augmented generation
    func generateWithTools(
        messages: [LLMMessage],
        system: String,
        tools: [ToolSchema]
    ) async throws -> LLMResponse
    
    // New: streaming with tools (for chat)
    func streamWithTools(
        messages: [LLMMessage],
        system: String,
        tools: [ToolSchema]
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

enum LLMStreamEvent {
    case textDelta(String)
    case toolUseStart(id: String, name: String)
    case toolUseInput(String)     // JSON input being streamed
    case toolUseEnd
    case messageEnd(stopReason: StopReason)
}
```

---

## Tool System

### Design Philosophy

Tools give the AI **eyes into the learning state.** The AI decides what to query based on the conversation context — we don't pre-inject everything.

### Tool Registry

```swift
struct ToolRegistry {
    let tools: [String: any AgentTool]
    
    var schemas: [ToolSchema] {
        tools.values.map(\.schema)
    }
    
    func execute(_ calls: [ToolCall]) async -> [ToolResult] {
        await withTaskGroup(of: ToolResult.self) { group in
            for call in calls {
                group.addTask {
                    guard let tool = self.tools[call.name] else {
                        return ToolResult(id: call.id, error: "Unknown tool")
                    }
                    return await tool.execute(input: call.input)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
    }
}

protocol AgentTool {
    var name: String { get }
    var description: String { get }
    var schema: ToolSchema { get }
    func execute(input: [String: Any]) async -> ToolResult
}
```

### Available Tools

#### Read-Only (Query)

| Tool | Input | Output | When AI Uses It |
|------|-------|--------|-----------------|
| `get_user_stats` | (none) | Total words, mastered count, streak, accuracy | "How am I doing overall?" |
| `get_due_words` | `limit?: Int` | List of words due today with priority | "What should I study?" |
| `get_word_history` | `word: String` | Times seen, ratings history, lapses, last review | "Why do I keep forgetting X?" |
| `get_weak_words` | `limit?: Int, criterion?: String` | Words with high lapse/low stability | "What are my weakest words?" |
| `get_confusion_pairs` | (none) | Pairs of words frequently confused | "What words do I mix up?" |
| `get_current_session` | (none) | Current session state (words done, accuracy, mode) | Context for mid-session advice |
| `get_recent_sessions` | `days?: Int` | Session summaries for last N days | "How was my week?" |
| `search_words` | `query: String, field?: String` | Words matching search criteria | "Words with root bene-" |
| `get_typing_errors` | `word?: String` | Common typos and error positions | "What letters do I mess up?" |

#### Write (Generate/Persist)

| Tool | Input | Output | When AI Uses It |
|------|-------|--------|-----------------|
| `save_word_note` | `wordId: String, note: String, type: NoteType` | Confirmation | After generating a helpful mnemonic |
| `mark_for_review` | `wordId: String, reason: String` | Confirmation | "You should review this soon" |
| `save_observation` | `content: String, type: ObsType` | Confirmation | Remembering something about user |

#### Meta

| Tool | Input | Output | When AI Uses It |
|------|-------|--------|-----------------|
| `get_memory` | `query?: String` | Relevant past observations | Recalling user preferences/history |

### Tool Schema Format (Anthropic-compatible)

```json
{
  "name": "get_word_history",
  "description": "Get the user's review history for a specific word, including times seen, all ratings given, lapse count, and last review date.",
  "input_schema": {
    "type": "object",
    "properties": {
      "word": {
        "type": "string",
        "description": "The word to look up (case-insensitive)"
      }
    },
    "required": ["word"]
  }
}
```

---

## Memory System (Hybrid / Progressive)

### Phase 1 (P0): Lightweight

```
┌─────────────────────────────────────────────┐
│  SQLite: ai_observations table              │
│  ┌─────────────────────────────────────┐    │
│  │ id | type | content | related_words │    │
│  │    | confidence | created_at        │    │
│  └─────────────────────────────────────┘    │
│                                              │
│  In-memory: current session messages         │
│  JSON blob: user_profile.json (preferences)  │
└─────────────────────────────────────────────┘
```

**Observations** are atomic facts the AI notices:
```
"User confuses aberrant and abhorrent" (type: confusion_pair)
"User prefers visual/image-based mnemonics" (type: preference)
"User tends to forget Latin-root words" (type: weakness)
"User knows the word 'benevolent' well — use as anchor" (type: strength)
"User responds well to Chinese phonetic associations" (type: preference)
```

**Schema:**
```sql
CREATE TABLE ai_observations (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,        -- confusion_pair, preference, weakness, strength, insight
    content TEXT NOT NULL,     -- Natural language observation
    related_words TEXT,        -- JSON array of related word IDs
    confidence REAL DEFAULT 1.0,
    source TEXT,               -- 'auto_extracted' | 'user_confirmed' | 'ai_generated'
    created_at TEXT NOT NULL,
    expires_at TEXT            -- NULL = permanent, else TTL
);

CREATE TABLE ai_conversations (
    id TEXT PRIMARY KEY,
    summary TEXT NOT NULL,     -- Compressed summary of conversation
    message_count INTEGER,
    key_topics TEXT,           -- JSON array
    created_at TEXT NOT NULL
);

-- User profile: single-row table, updated periodically
CREATE TABLE ai_user_profile (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    learning_style TEXT,       -- JSON: preferred mnemonic types, session length, etc.
    weak_areas TEXT,           -- JSON: root families, word categories
    strong_areas TEXT,         -- JSON
    goals TEXT,                -- JSON: exam date, target word count
    updated_at TEXT NOT NULL
);
```

### Phase 2 (Future): Full Memory

- Conversation persistence with compression (keep last 3 full, compress older to summaries)
- Automatic observation extraction after each conversation (via Haiku)
- Profile auto-update (weekly batch job: observations → updated profile)
- Embedding-based retrieval for relevant observations
- Observation deduplication and conflict resolution

### Memory Read/Write Flow

```
Chat Start:
  → Load user_profile (always, cheap)
  → Load recent observations (last 20, sorted by relevance)
  → Inject into system prompt
  
During Chat:
  → AI uses `get_memory` tool if it needs specific history
  → AI uses `save_observation` if it notices something worth remembering
  
Chat End:
  → Auto-extract observations from conversation (async, uses Haiku)
  → Save conversation summary
  
Weekly:
  → Compress observations into updated profile
  → Prune expired/low-confidence observations
```

---

## Proactive Engine

### Event-Driven Architecture

```swift
@Observable
final class ProactiveEngine {
    private let runtime: AICompanionRuntime
    private let tipCache: TipCache
    
    // Throttling
    private var lastTipTime: Date = .distantPast
    private var sessionTipCount = 0
    private let minInterval: TimeInterval = 45    // Seconds between tips
    private let maxTipsPerSession = 8
    
    // Event handlers
    func onWordShown(_ word: Word, context: SessionContext) { ... }
    func onRating(_ word: Word, _ rating: Rating, context: SessionContext) { ... }
    func onConsecutiveFailures(count: Int, words: [Word]) { ... }
    func onSessionStart(dueCount: Int, newCount: Int) { ... }
    func onSessionEnd(stats: SessionStats) { ... }
    func onIdle(duration: TimeInterval) { ... }
    func onTypingError(_ word: Word, position: Int, expected: Character) { ... }
}
```

### Tip Priority & Throttling

```swift
enum TipPriority: Int, Comparable {
    case low = 0        // General encouragement, trivia
    case medium = 1     // Pattern-based suggestions
    case high = 2       // Specific confusion fix, after failure
    case critical = 3   // Session start/end briefings (always show)
}

// Throttle logic
func shouldShowTip(priority: TipPriority) -> Bool {
    if priority == .critical { return true }
    if sessionTipCount >= maxTipsPerSession { return false }
    if Date().timeIntervalSince(lastTipTime) < minInterval { return false }
    return true
}
```

### Tip Content Sources (混合策略)

```
┌─────────────────────────────────────────────────────────────┐
│                    Tip Resolution Order                       │
│                                                              │
│  1. Pre-generated cache (instant, <1ms)                      │
│     └─ Generated at session start for weak words             │
│     └─ Generated at build time for mnemonics                 │
│                                                              │
│  2. Template-based (instant, no API)                         │
│     └─ "You've seen {word} {n} times, accuracy {x}%"        │
│     └─ "Remember: {word} comes from {root} meaning {x}"     │
│                                                              │
│  3. On-demand generation (async, 1-3s)                       │
│     └─ Triggered by specific patterns (consecutive fails)    │
│     └─ Uses Haiku for speed                                  │
│     └─ Result cached for future use                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Pre-generation (Session Start)

```swift
/// Called when a study session begins
func prepareSessionTips(words: [Word], memory: MemoryStore) async {
    // Only generate for words likely to need help
    let needsTips = words.filter { word in
        word.lapseCount > 1 ||              // Failed before
        word.lastRating == .again ||        // Failed recently
        word.stability < 5.0 ||            // Still fragile
        memory.hasConfusionPair(for: word)  // Known confusion
    }
    
    guard !needsTips.isEmpty else { return }
    
    // Batch request (single API call, Haiku for speed)
    let tips = try await batchGenerateTips(
        words: needsTips,
        observations: memory.getRelevantObservations(for: needsTips),
        model: .haiku  // Fast + cheap for short tips
    )
    
    tipCache.store(tips)  // Available instantly during session
}
```

### Event → Tip Examples

| Event | Condition | Tip Source | Content |
|-------|-----------|------------|---------|
| Word shown | Has cached tip | Cache | "Last time: confused with {X}. Key: {distinction}" |
| Word shown | Is new word, has root | Template | "Root breakdown: {prefix}+{root}+{suffix}" |
| Rating: Again | 2nd+ lapse | Cache/Generate | "Try this: {new mnemonic approach}" |
| 3× Again in row | Pattern detected | Generate (async) | "These are all {category}. Want a story linking them?" |
| Session start | Has due words | Generate (briefing) | "Today: {n} reviews, focus on {weak area}" |
| Session end | Stats available | Generate (summary) | "78% accuracy (↑5%). Weakest: {cluster}" |
| Idle > 30s | On card back | Template | "Take your time. This word has {n} syllables: {breakdown}" |
| Typing error | Position pattern | Template/Cache | "You always put 'i' before 'e' in {word} — it's the opposite" |

---

## Context Builder

### System Prompt Structure

```
┌─────────────────────────────────────────────────┐
│  [Persona]                                       │
│  You are a GRE vocabulary tutor embedded in a    │
│  learning app. You're patient, concise, and      │
│  connect English words to Chinese where helpful. │
│                                                  │
│  [User Profile] (from memory)                    │
│  - Learning style: visual mnemonics preferred    │
│  - Weak areas: Latin roots, abstract adjectives  │
│  - Streak: 12 days, mastered 340/6500 words      │
│  - Exam: GRE in 45 days                         │
│                                                  │
│  [Recent Observations] (from memory)             │
│  - Confuses aberrant/abhorrent (3 times)         │
│  - Prefers word-root breakdowns over stories     │
│  - Best retention on morning sessions            │
│                                                  │
│  [Current Context] (mode-dependent)              │
│  - Mode: Flashcard study session                 │
│  - Current word: "equivocate" (3rd time seen)    │
│  - Session so far: 8/20 done, 75% accuracy       │
│  - Last 3 ratings: Good, Again, Hard             │
│                                                  │
│  [Instructions]                                  │
│  - Be concise (1-3 sentences for tips)           │
│  - Use tools to look up specific data            │
│  - Never make up word history — use tools        │
│  - Speak in Chinese when explaining, English for │
│    vocabulary terms                               │
└─────────────────────────────────────────────────┘
```

### Mode-Specific Context Injection

```swift
enum AppMode {
    case flashcard(currentWord: Word?, sessionProgress: SessionProgress)
    case typing(currentWord: Word?, chapter: Int, errors: [TypingError])
    case quiz(question: QuizQuestion?, userAnswer: String?)
    case chat          // No additional context beyond profile
    case dashboard     // Stats summary context
    case library       // Current word list being browsed
}

struct ContextBuilder {
    func build(mode: AppMode, memory: MemoryStore, currentWord: Word?) async -> String {
        var sections: [String] = []
        
        // Always include
        sections.append(Persona.tutor)
        sections.append(await memory.getUserProfileSection())
        sections.append(await memory.getRecentObservationsSection(limit: 10))
        
        // Mode-specific
        switch mode {
        case .flashcard(let word, let progress):
            if let word {
                sections.append(buildWordContext(word, memory: memory))
            }
            sections.append(buildSessionContext(progress))
            
        case .typing(let word, let chapter, let errors):
            if let word {
                sections.append(buildWordContext(word, memory: memory))
                sections.append(buildTypingContext(errors))
            }
            
        case .quiz(let question, let answer):
            if let q = question {
                sections.append(buildQuizContext(q, userAnswer: answer))
            }
            
        default:
            break
        }
        
        sections.append(Persona.instructions)
        return sections.joined(separator: "\n\n")
    }
}
```

---

## LLM Strategy (混合)

### Model Selection

| Use Case | Model | Latency | Cost | Notes |
|----------|-------|---------|------|-------|
| Chat (full conversation) | claude-sonnet | ~2s | Medium | Best quality for multi-turn |
| Batch tip pre-gen | claude-haiku | ~500ms | Low | Speed + cost for short outputs |
| Observation extraction | claude-haiku | ~1s | Low | Post-turn async processing |
| Daily briefing | claude-sonnet | ~2s | Medium | Once per day, quality matters |
| Quick reactive tip | claude-haiku | ~500ms | Low | After rating, needs speed |
| Weekly report | claude-sonnet | ~3s | Medium | Once per week |

### Cost Budget (Estimated)

```
Per day (active user, 30 min session):
  - Session start briefing (Sonnet): 1 call × ~500 tokens = ~$0.005
  - Batch tip pre-gen (Haiku): 1 call × ~2000 tokens = ~$0.002
  - Reactive tips (Haiku): ~3 calls × ~200 tokens = ~$0.001
  - Chat interactions (Sonnet): ~5 exchanges × ~1000 tokens = ~$0.03
  - Observation extraction (Haiku): 1 call × ~500 tokens = ~$0.001
  - Session summary (Sonnet): 1 call × ~500 tokens = ~$0.005
  
  Total: ~$0.04/day = ~$1.20/month
```

### Caching Strategy

```swift
struct TipCache {
    // In-memory: current session's pre-generated tips
    private var sessionTips: [String: TipContent] = [:]  // wordId → tip
    
    // SQLite: persistent cache for generated content
    // Key: hash(wordId + contextHash)
    // Value: generated content + timestamp
    // TTL: 7 days (or until word state changes significantly)
    
    func get(wordId: String, context: CacheContext) -> TipContent? {
        // 1. Check session cache (instant)
        if let tip = sessionTips[wordId] { return tip }
        
        // 2. Check persistent cache (fast SQLite lookup)
        if let cached = db.getCachedTip(wordId: wordId, context: context),
           !cached.isExpired {
            return cached.content
        }
        
        return nil  // Cache miss → caller decides whether to generate
    }
}
```

---

## Data Schema Extensions

### New Tables

```sql
-- AI-generated tips cache
CREATE TABLE ai_tip_cache (
    id TEXT PRIMARY KEY,
    word_id TEXT NOT NULL,
    tip_type TEXT NOT NULL,        -- 'mnemonic', 'confusion', 'pattern', 'encouragement'
    content TEXT NOT NULL,
    context_hash TEXT,             -- Hash of context used to generate (for invalidation)
    model TEXT,                    -- Which model generated it
    created_at TEXT NOT NULL,
    expires_at TEXT,
    FOREIGN KEY (word_id) REFERENCES words(id)
);
CREATE INDEX idx_tip_cache_word ON ai_tip_cache(word_id);

-- Observations (memory)
CREATE TABLE ai_observations (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,            -- 'confusion_pair', 'preference', 'weakness', 'strength', 'insight'
    content TEXT NOT NULL,
    related_words TEXT,            -- JSON array of word spellings
    confidence REAL DEFAULT 1.0,
    source TEXT DEFAULT 'auto',   -- 'auto' | 'user_confirmed' | 'chat_extracted'
    created_at TEXT NOT NULL,
    expires_at TEXT
);
CREATE INDEX idx_obs_type ON ai_observations(type);
CREATE INDEX idx_obs_created ON ai_observations(created_at);

-- Conversation summaries (don't store full history, just summaries)
CREATE TABLE ai_conversations (
    id TEXT PRIMARY KEY,
    summary TEXT NOT NULL,
    topics TEXT,                   -- JSON array of topics discussed
    observations_extracted INTEGER DEFAULT 0,
    message_count INTEGER,
    created_at TEXT NOT NULL
);

-- User profile (single row, updated periodically)
CREATE TABLE ai_user_profile (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    learning_style TEXT,          -- JSON
    weak_areas TEXT,              -- JSON
    strong_areas TEXT,            -- JSON  
    preferences TEXT,             -- JSON (mnemonic style, language, verbosity)
    goals TEXT,                   -- JSON (exam date, daily target)
    summary TEXT,                 -- Natural language profile summary (for system prompt)
    updated_at TEXT NOT NULL
);
```

---

## Implementation Phases

### P0: Agent Foundation (Core Loop + Chat UI)

**Goal:** Working chat panel with tool-augmented responses.

Files to create/modify:
```
Services/
├── AICompanion/
│   ├── AICompanionRuntime.swift    # Agent loop (send, tool execution)
│   ├── ContextBuilder.swift         # System prompt assembly
│   ├── ToolRegistry.swift           # Tool discovery + execution
│   └── Tools/                       # Individual tool implementations
│       ├── GetUserStatsTool.swift
│       ├── GetWordHistoryTool.swift
│       ├── GetWeakWordsTool.swift
│       └── SearchWordsTool.swift
├── AIProviders/
│   ├── AIProvider.swift             # Extended with tool support
│   └── ClaudeProvider.swift         # Real API implementation
Views/
└── AI/
    ├── AIPanelView.swift            # Right side panel container
    ├── AIChatView.swift             # Message list + input
    └── AIMessageView.swift          # Single message rendering
```

Key deliverables:
- [ ] ClaudeProvider: real API calls with tool support (Messages API)
- [ ] Agent loop: message → LLM → tool_use → execute → loop
- [ ] 4 read-only tools: stats, word history, weak words, search
- [ ] Side panel UI: collapsible, chat with streaming
- [ ] Basic system prompt with persona

### P1: Memory & Context (Observations + Profile)

**Goal:** AI remembers across sessions, context-aware responses.

Files:
```
Services/
└── AICompanion/
    ├── MemoryStore.swift            # CRUD for observations + profile
    ├── ObservationExtractor.swift   # Post-chat extraction (Haiku)
    └── ContextBuilder.swift         # Now includes memory sections
```

Key deliverables:
- [ ] SQLite tables for observations + profile
- [ ] `get_memory` and `save_observation` tools
- [ ] Post-conversation observation extraction
- [ ] Context builder injects profile + observations into system prompt
- [ ] Manual "remember this" via chat ("记住我讨厌visual mnemonics")

### P2: Proactive Tips (Session Integration)

**Goal:** AI speaks up during study with useful, non-intrusive tips.

Files:
```
Services/
└── AICompanion/
    ├── ProactiveEngine.swift        # Event handling + throttling
    ├── TipCache.swift               # In-memory + persistent cache
    └── TipGenerator.swift           # Batch + on-demand generation
Views/
└── AI/
    ├── TipBubbleView.swift          # Floating tip in panel
    └── AIPanelView.swift            # Updated: tip zone + chat zone
```

Key deliverables:
- [ ] Event system: word shown, rating given, session start/end
- [ ] Tip cache with pre-generation at session start
- [ ] Throttling logic (min interval, max per session)
- [ ] Tip display in panel (auto-dismiss, priority levels)
- [ ] Template-based tips for instant display (no API needed)

### P3: Flashcard Deep Integration

**Goal:** AI tips appear contextually on flashcard back, integrated with study flow.

Key deliverables:
- [ ] CardBackView: shows cached AI tip inline
- [ ] Post-rating: "Again" triggers async tip generation
- [ ] Confusion pair detection: auto-compare on known pairs
- [ ] Typing mode: error pattern tips
- [ ] "Ask AI about this word" button on card

### P4: Advanced Memory + Weekly Reports

**Goal:** Long-term learning companion behavior.

Key deliverables:
- [ ] Weekly profile auto-update from observations
- [ ] Observation deduplication and confidence decay
- [ ] Weekly learning report generation
- [ ] Strategy recommendations based on patterns
- [ ] Exam countdown mode activation

---

## Persona & Prompts

### Base Persona

```
You are an AI vocabulary tutor embedded in Erudite, a GRE preparation app. 

Your role:
- Help the user master GRE vocabulary efficiently
- Notice patterns in their learning and offer targeted advice  
- Remember their preferences and adapt your style
- Be concise — you're a study companion, not a lecturer

Style:
- Default language: Chinese for explanations, English for vocabulary terms
- Concise: 1-3 sentences for tips, longer only for explicit questions
- Connect words to Chinese (phonetic associations, character parallels)
- Use word roots and etymology as primary mnemonic strategy
- Be encouraging but honest about areas needing work

Constraints:
- Never make up review history — use the get_word_history tool
- Never guess statistics — use get_user_stats tool
- If unsure about a word's etymology, say so
- Don't overwhelm with unsolicited advice — be selective
```

### Tip Generation Prompt (Batch)

```
You are generating study tips for a GRE learner. For each word below, 
generate ONE concise tip (1-2 sentences, Chinese) that addresses their 
specific struggle pattern.

Learner context:
{user_profile_summary}
{relevant_observations}

Words needing tips:
{word_list_with_history}

Guidelines:
- If there's a known confusion pair, disambiguate
- If high lapse count, try a new mnemonic angle
- If spelling errors, highlight the tricky part
- Connect to Chinese where it helps
- Never repeat a tip the user has already seen

Output JSON: [{"wordId": "...", "tip": "...", "type": "..."}]
```

---

## Open Design Notes

### What We're NOT Doing (Yet)

1. **Local LLM**: Claude API only. No on-device inference. Offline = cached content only.
2. **Voice interaction**: Text-only for now. TTS is for pronunciation, not AI.
3. **Multi-user**: Single user only. No collaboration features.
4. **Autonomous actions**: AI cannot modify FSRS state or skip words. It can only suggest and annotate.
5. **Image generation**: No visual mnemonics generation (text descriptions only).

### Future Exploration

- **Embedding-based memory retrieval**: When observations grow large, use embeddings for relevance
- **FSRS-AI co-training**: AI suggests FSRS parameter adjustments based on patterns
- **Exam simulation**: AI generates full GRE verbal section practice
- **Spaced repetition for tips**: Don't show the same tip too often; rotate strategies
