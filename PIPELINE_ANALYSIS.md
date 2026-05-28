# Erudite Word Database Pipeline - Comprehensive Analysis

**Date**: 2026-05-27  
**Document**: Complete pipeline exploration for the Erudite vocabulary app  
**Scope**: Data sources, transformations, schema, and current coverage

---

## Executive Summary

The Erudite word database pipeline is a multi-stage process that:

1. **Consumes** multiple raw vocabulary sources (GRE, TOEFL, SAT lists)
2. **Transforms** them using Python scripts into normalized JSON format
3. **Outputs** two JSON files consumed by the Swift/iOS app:
   - `words.json` - Comprehensive word database (13,112 words)
   - `wordbooks.json` - Word book manifests (6 books)

**Current Status**: Partially enriched (79.6% have phonetics, 45.6% have synonyms, 32.6% have mnemonics; 0% have antonyms/roots/tags)

---

## 1. DATA SOURCES

### 1.1 Primary Source: GRE_3.json (新东方)

**File**: `/Users/frankshi/Projects/app/erudite/data/raw/GRE_3.json`

- **Format**: Line-delimited JSON (JSONL)
- **Word Count**: 6,515 words
- **Source**: [kajweb/dict](https://github.com/kajweb/dict) - 新东方 GRE vocabulary
- **Role**: Primary data source with richest field coverage

**Structure per entry**:
```json
{
  "wordRank": 1,
  "headWord": "hale",
  "content": {
    "word": {
      "wordHead": "hale",
      "wordId": "GRE_3_1",
      "content": {
        "trans": [
          {
            "pos": "adj",
            "tranCn": "精神矍铄的（尤指老人）；强壮的",
            "tranOther": ""
          }
        ],
        "sentence": {
          "sentences": [
            {
              "sContent": "She's still hale and hearty at 74.",
              "sCn": "她74岁仍然精神矍铄。"
            }
          ],
          "desc": "例句"
        },
        "syno": {
          "synos": [
            {
              "pos": "adj",
              "tran": "精神矍铄的（尤指老人）；强壮的",
              "hwds": [
                {"w": "strong"},
                {"w": "tough"}
              ]
            }
          ],
          "desc": "同义词"
        },
        "remMethod": {
          "val": "hal(呼吸) + e → 呼吸得很好的 → 精神矍铄的",
          "desc": "记忆"
        },
        "usphone": "heɪl",
        "ukphone": "heɪl",
        "usspeech": "hale&type=2",
        "ukspeech": "hale&type=1"
      }
    }
  },
  "bookId": "GRE_3"
}
```

**Fields Available**:
- ✅ Chinese definitions (`tranCn`)
- ✅ English translations (`tranOther`)
- ✅ Part of speech (`pos`)
- ✅ Example sentences (`sentence.sentences[].sContent`)
- ✅ Synonym groups (`syno.synos[].hwds[]`)
- ✅ Mnemonics (`remMethod.val`)
- ✅ Phonetics (US: `usphone`, UK: `ukphone`)
- ⚠️ Related words (`relWord`) - present but not used
- ❌ Morpheme breakdowns (not structured)
- ❌ Antonyms (not present)
- ❌ Tags (not present)

**Coverage in current build**:
- 6,515 GRE words → 524 Tier 1 (Core) + 1,750 Tier 2 (Common) + 4,241 Tier 3 (Advanced)

---

### 1.2 Supplement Source: GRE_2.json (有道)

**File**: `/Users/frankshi/Projects/app/erudite/data/raw/GRE_2.json`

- **Format**: Line-delimited JSON (JSONL)
- **Word Count**: 7,199 words
- **Source**: [kajweb/dict](https://github.com/kajweb/dict) - 有道 GRE vocabulary
- **Role**: Backup source for words not in GRE_3; currently not used actively in pipeline

**Status**: Loaded but not merged into final output (GRE_3 is sufficient)

---

### 1.3 Frequency Signal: L-GRE-再要你命3000.csv

**File**: `/Users/frankshi/Projects/app/erudite/data/raw/L-GRE-再要你命3000.csv`

- **Format**: CSV (word, pos+chinese, english)
- **Word Count**: 3,033 words
- **Source**: [LER0ever/GRE-CN](https://github.com/LER0ever/GRE-CN) - Popular GRE word list

**Purpose**: Cross-reference signal for frequency tiering

**Sample entries**:
```
abandon,"v./n.放纵\nv.放弃","1.freedom from constraint\n2.withdraw"
abase,"v. 降低（地位、职位、威望或尊严）","lower"
abash,"v.使尴尬，使羞愧","embarrass"
```

---

### 1.4 Frequency Signal: L-GRE-MagooshFlashcard.csv

**File**: `/Users/frankshi/Projects/app/erudite/data/raw/L-GRE-MagooshFlashcard.csv`

- **Format**: CSV (word, definition, example, ...)
- **Word Count**: 1,008 words
- **Source**: [LER0ever/GRE-CN](https://github.com/LER0ever/GRE-CN) - Magoosh GRE flashcard deck

**Purpose**: 
1. Cross-reference signal for frequency tiering
2. English example sentences (supplements GRE_3)

**Sample entries**:
```csv
aberrant,adjective: markedly different from an accepted norm,"When the financial director started screaming..."
aberration,noun: a deviation from what is normal or expected,"Aberrations in climate have become the norm..."
abjure,verb: formally reject or give up (as a belief),"While the church believed that Galileo abjured..."
```

---

### 1.5 Word Book Sources (qwerty-learner Format)

**Format**: JSON array of objects

**Files**:
| File | Exam | Wordbook Name | Word Count |
|------|------|---------------|-----------|
| `GRE3000_3_T.json` | GRE | 再要你命3000 (Sequential) | 3,041 |
| `gre-ciyileiji.json` | GRE | 词以类记 (Thematic) | 8,384 |
| `GRE_equivalent.json` | GRE | 等价词 (Equivalent words) | 827 |
| `TOEFL_3_T.json` | TOEFL | 核心 (Core) | 4,264 |
| `Categorized_TOEFL_Vocabulary_by_Zhanghongyan.json` | TOEFL | 词以类记 (Thematic) | 3,669 |
| `SAT_3_T.json` | SAT | 核心 (Core) | 4,463 |

**Entry structure**:
```json
{
  "name": "assent",
  "trans": ["同意"],
  "usphone": "əˈsɛnt",
  "ukphone": "əˈsent"
}
```

These are minimal entries used to create wordbooks. Words not in the main GRE_3 database get minimal entries from these sources.

---

## 2. PIPELINE ARCHITECTURE

### 2.1 Build Process (Two-Stage)

#### Stage 1: `build_worddb.py` - Primary Word Database

**Input**:
- GRE_3.json (primary)
- GRE_2.json (backup)
- L-GRE-再要你命3000.csv (frequency signal)
- L-GRE-MagooshFlashcard.csv (frequency signal + examples)

**Process**:
```
1. Load GRE_3 (6,515 words)
2. Load GRE_2 (7,199 words) - as backup
3. Load frequency signals (再要你命3000, Magoosh)
4. For each GRE_3 word:
   a. Extract definitions, examples, mnemonics, phonetics, synonyms
   b. Determine frequency tier (1/2/3) by cross-reference
   c. Supplement with Magoosh example if available
5. Assign List/Unit indices (for 打卡 study structure)
6. Write words.json
```

**Output**: `words.json` (v2.0)
- Single flat array of Word objects
- List/Unit indices for sequential study organization
- ~5.6 MB, 6,515 words

---

#### Stage 2: `build_multibook.py` - Multi-Wordbook Integration

**Input**:
- Existing words.json from Stage 1
- 6 qwerty-learner wordbook JSON files

**Process**:
```
1. Load existing rich words.json database (keyed by spelling)
2. For each wordbook:
   a. Parse entries (name, trans, phonetic)
   b. Extract word IDs in order
   c. For words not in existing DB:
      - Create minimal Word entry (spelling + Chinese from source)
   d. Build wordbook manifest entry
3. Merge new words into word database
4. Strip legacy listIndex/unitIndex from words
5. Write updated words.json and wordbooks.json
```

**Output**: 
- Updated `words.json` (v3.0) - 13,112 total words
- New `wordbooks.json` - 6 book manifests

---

### 2.2 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ RAW DATA (data/raw/)                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  GRE_3.json (6,515)  ──┐                                   │
│  GRE_2.json (7,199)  ──┤                                   │
│  再要你命3000.csv    ──┼──→ [build_worddb.py]             │
│  MagooshFlashcard.csv ┘    (Primary enrichment)            │
│                            │                               │
└────────────────────────────┼───────────────────────────────┘
                             │
                             ▼
                    words.json (v2.0)
                    6,515 words
                    Rich: definitions, examples,
                    mnemonics, synonyms
                             │
┌────────────────────────────┼───────────────────────────────┐
│ WORDBOOK SOURCES                                           │
├────────────────────────────┼───────────────────────────────┤
│  GRE3000_3_T.json        │                                │
│  gre-ciyileiji.json      ├──→ [build_multibook.py]       │
│  GRE_equivalent.json     │    (Merge wordbooks)           │
│  TOEFL_3_T.json          │                                │
│  ...                     │                                │
└────────────────────────────┼───────────────────────────────┘
                             │
                    ┌────────┴──────────┐
                    ▼                   ▼
            words.json (v3.0)    wordbooks.json
            13,112 words         6 books
            + minimal entries    manifest
             for new words
```

---

## 3. DATA TRANSFORMATION & ENRICHMENT

### 3.1 Word Struct (Swift Model)

```swift
struct Word: Identifiable, Codable, Hashable {
    let id: String                          // lowercase spelling
    let spelling: String                    // original casing
    let phonetic: String?                   // /ˈfɒnɛtɪk/
    let definitions: [Definition]
    let roots: MorphemeBreakdown?
    let synonymGroups: [[String]]
    let antonyms: [String]
    let sentiment: Sentiment                // enum: positive/negative/neutral/ambivalent
    let frequency: FrequencyTier            // enum: core(1)/common(2)/advanced(3)
    let examples: [Example]
    let mnemonics: [String]
    let tags: [String]
}

struct Definition {
    let partOfSpeech: String                // "n", "v", "adj", etc.
    let english: String
    let chinese: String
}

struct MorphemeBreakdown {
    let segments: [Morpheme]
    let logic: String
}

struct Morpheme {
    let text: String
    let type: MorphemeType                  // prefix/root/suffix
    let meaning: String
}

struct Example {
    let sentence: String
    let source: String                      // "dictionary"/"magoosh"/"generated"/"official"/"custom"
}
```

---

### 3.2 Field Extraction & Transformation Rules

#### phonetic (79.6% coverage - 10,442 words)

**Source**: GRE_3 → `content.word.content.{usphone, ukphone}`

**Transformation**:
```python
# Prefer US pronunciation
for key in ["usphone", "ukphone", "phone"]:
    if key in content and content[key]:
        ph = content[key].strip()
        if ph and not ph.startswith("/"):
            ph = f"/{ph}/"
        return ph
```

**Current Data**:
- All GRE_3 words have phonetics
- Wordbook source words: 79.6% have phonetics (from qwerty-learner)

---

#### definitions (100% coverage - all 13,112 words)

**Source**: GRE_3 → `content.word.content.trans[]`

**Transformation**:
```python
def parse_definitions(content: dict) -> list[Definition]:
    defs = []
    for t in content.get("trans", []):
        pos = t.get("pos", "").strip()
        english = t.get("tranOther", "").strip()
        chinese = t.get("tranCn", "").strip()
        if chinese or english:
            defs.append(Definition(
                partOfSpeech=pos,
                english=english,
                chinese=chinese,
            ))
    return defs
```

**Current Coverage**:
- 13,112 words have at least 1 definition
- 609 words (4.6%) have multiple definitions
- POS distribution:
  - Noun (n): 4,415 words
  - Adjective (adj): 2,988 words
  - Verb (v): 2,181 words
  - Other (vt, vi, adv, etc.): 528 words
  - Missing/empty POS: 3,791 words

---

#### synonymGroups (45.6% coverage - 5,977 words)

**Source**: GRE_3 → `content.word.content.syno.synos[]`

**Transformation**:
```python
def parse_synonyms(content: dict) -> list[list[str]]:
    groups = []
    syno = content.get("syno", {})
    if not syno:
        return groups
    for syn_group in syno.get("synos", []):
        hwds = syn_group.get("hwds", [])
        group = [h["w"] for h in hwds if "w" in h]
        if group:
            groups.append(group)
    return groups
```

**Current Data**:
- GRE_3 words: ~91% have synonym groups
- Wordbook words: 0% (minimal entries)

**Example**: "abate" has 2 synonym groups:
```json
[
  ["reduce", "lessen"],
  ["decrease", "diminish"]
]
```

---

#### examples (45.0% coverage - 5,896 words)

**Source**: 
1. GRE_3 → `content.word.content.sentence.sentences[]`
2. Magoosh CSV supplement

**Transformation**:
```python
def parse_examples(content: dict) -> list[Example]:
    examples = []
    sentence_data = content.get("sentence", {})
    if not sentence_data:
        return examples
    for s in sentence_data.get("sentences", []):
        text = s.get("sContent", "").strip()
        text = text.replace("<b>", "").replace("</b>", "")
        if text:
            examples.append(Example(sentence=text, source="dictionary"))
    return examples

# Then supplement with Magoosh if available and richer
if magoosh_data and magoosh_data.get("example"):
    magoosh_example = magoosh_data["example"].strip()
    if magoosh_example and len(magoosh_example) > 20:
        examples.append(Example(sentence=magoosh_example, source="magoosh"))
```

**Current Distribution**:
- Words with GRE_3 examples: 7,967 (dictionary source)
- Words with Magoosh examples: 709 (magoosh source)
- Total unique words with examples: 5,896 (45.0%)

---

#### mnemonics (32.6% coverage - 4,278 words)

**Source**: GRE_3 → `content.word.content.remMethod.val`

**Transformation**:
```python
def parse_mnemonic(content: dict) -> list[str]:
    rem = content.get("remMethod", {})
    if rem and rem.get("val"):
        return [rem["val"].strip()]
    return []
```

**Current Data**:
- 4,278 words have mnemonics
- Format: Chinese morpheme breakdown with logic
- Example: "hal(呼吸) + e → 呼吸得很好的 → 精神矍铄的"

---

#### antonyms (0% coverage - currently empty)

**Status**: ❌ **NOT POPULATED**

**Expected Implementation**: 
- Would require AI enrichment or external data source
- No antonyms in current GRE_3 structure
- Should be populated via batch AI operation or external API

---

#### roots / MorphemeBreakdown (0% coverage - currently null)

**Status**: ❌ **NOT POPULATED**

**Expected Structure**:
```json
{
  "segments": [
    {
      "text": "pre",
      "type": "prefix",
      "meaning": "before"
    },
    {
      "text": "fix",
      "type": "root",
      "meaning": "fasten"
    }
  ],
  "logic": "prefix + root = word meaning"
}
```

**Current Gap**: 
- mnemonics field contains text mnemonics
- roots field should contain structured morpheme data
- Possible source: Parse mnemonics into structured format, or AI enrichment

---

#### tags (0% coverage - currently empty)

**Status**: ❌ **NOT POPULATED**

**Possible Uses**:
- Part of speech tags (adj, n, v, etc.) - already in definitions.partOfSpeech
- Semantic categories (emotions, abstract, concrete, etc.)
- Usage domain tags (literary, technical, colloquial, etc.)
- Difficulty level tags
- Test-specific tags (GRE, TOEFL, SAT)

---

#### sentiment (100% coverage but all "neutral")

**Status**: ⚠️ **PARTIALLY IMPLEMENTED**

**Current Implementation**:
```python
sentiment = "neutral"  # hardcoded for all words
```

**Expected**: Should distinguish:
- `positive`: words with positive connotations (beautiful, heroic, brilliant)
- `negative`: words with negative connotations (ugly, tragic, dismal)
- `neutral`: objective words (tree, table, run)
- `ambivalent`: words that can have both (ambition, competition)

**Gap**: No sentiment classification in pipeline; would require AI enrichment

---

#### frequency / FrequencyTier (100% coverage)

**Source**: Cross-reference logic with frequency signals

**Algorithm**:
```python
def determine_frequency(word: str, zyy_words: set[str], magoosh_words: set[str]) -> int:
    in_zyy = word in zyy_words
    in_magoosh = word in magoosh_words
    if in_zyy and in_magoosh:
        return 1  # core (BOTH sources)
    elif in_zyy:
        return 2  # common (再要你命3000 only)
    else:
        return 3  # advanced (GRE_3 only)
```

**Current Distribution**:
- Tier 1 (Core): 524 words (4.0%) - in both Magoosh AND 再要你命3000
- Tier 2 (Common): 1,750 words (13.3%) - in 再要你命3000 only
- Tier 3 (Advanced): 10,838 words (82.7%) - not in frequency signals

---

### 3.3 JSON Schema (Output Format)

**Structure**: words.json v3.0

```json
{
  "version": "3.0",
  "generated_at": "2026-05-26",
  "word_count": 13112,
  "words": [
    {
      "id": "abacus",
      "spelling": "abacus",
      "phonetic": "/ˋæbəkəs/",
      "frequency": 3,
      "sentiment": "neutral",
      "definitions": [
        {
          "partOfSpeech": "n",
          "english": "",
          "chinese": "算盘"
        }
      ],
      "synonymGroups": [],
      "antonyms": [],
      "examples": [],
      "mnemonics": [],
      "tags": [],
      "roots": null
    },
    ...
  ]
}
```

**Note**: Sorted alphabetically by id for clean git diffs in v3.0

---

## 4. WORDBOOKS INTEGRATION

### 4.1 wordbooks.json Structure

**File**: `/Users/frankshi/Projects/app/erudite/Erudite/Erudite/Resources/Data/wordbooks.json`

```json
{
  "version": "1.0",
  "generated_at": "2026-05-26",
  "books": [
    {
      "id": "gre-3000",
      "name": "GRE 再要你命3000",
      "exam": "GRE",
      "source": "qwerty-learner",
      "structure": "sequential",
      "wordCount": 3036,
      "words": ["assent", "sulk", "patrician", ...]
    },
    ...
  ]
}
```

---

### 4.2 Word Book Definitions

| ID | Name | Exam | Structure | Words | Purpose |
|---|---|---|---|---|---|
| `gre-3000` | GRE 再要你命3000 | GRE | Sequential | 3,036 | Core GRE vocabulary |
| `gre-ciyileiji` | GRE 词以类记 | GRE | Thematic | 8,384 | GRE words grouped by meaning |
| `gre-equivalent` | GRE 等价词 | GRE | Sequential | 827 | GRE equivalent word pairs |
| `toefl-core` | TOEFL 核心 | TOEFL | Sequential | 4,264 | Core TOEFL vocabulary |
| `toefl-ciyileiji` | TOEFL 词以类记 | TOEFL | Thematic | 3,669 | TOEFL words grouped by meaning |
| `sat-core` | SAT 核心 | SAT | Sequential | 4,463 | Core SAT vocabulary |

---

### 4.3 Minimal Word Generation

Words appearing in wordbooks but not in the primary GRE_3 database get minimal entries:

```python
def create_minimal_word(spelling: str, chinese: Optional[str], phonetic: Optional[str]) -> dict:
    definitions = []
    if chinese:
        # Try to extract POS from Chinese definition
        pos = ""
        cn = chinese
        for prefix in ["n．", "v．", "adj．", "adv．", "n. ", "v. ", ...]:
            if chinese.startswith(prefix):
                pos = prefix.rstrip("．. ")
                cn = chinese[len(prefix):]
                break
        definitions.append({
            "partOfSpeech": pos,
            "english": "",
            "chinese": cn,
        })

    return {
        "id": spelling,
        "spelling": spelling,
        "phonetic": phonetic,
        "frequency": 3,  # advanced by default for non-GRE words
        "sentiment": "neutral",
        "definitions": definitions,
        "synonymGroups": [],
        "antonyms": [],
        "examples": [],
        "mnemonics": [],
        "tags": [],
        "roots": None,
    }
```

**Current Coverage**:
- 6,515 words from GRE_3 (rich data)
- 6,597 minimal entries from wordbooks (sparse data)
- Total: 13,112 unique words

---

## 5. FIELD COVERAGE SUMMARY

### 5.1 Population Statistics

| Field | Count | % Coverage | Notes |
|-------|-------|-----------|-------|
| definitions | 13,112 | 100% | All words have at least 1 definition |
| phonetic | 10,442 | 79.6% | Present for GRE_3 + qwerty-learner with usphone/ukphone |
| synonymGroups | 5,977 | 45.6% | Only from GRE_3 source |
| examples | 5,896 | 45.0% | GRE_3 dictionary + Magoosh supplement |
| mnemonics | 4,278 | 32.6% | GRE_3 remMethod only |
| frequency | 13,112 | 100% | All words have frequency tier (1/2/3) |
| sentiment | 13,112 | 0%* | All set to "neutral" (no actual differentiation) |
| antonyms | 0 | 0% | **NOT POPULATED** |
| roots | 0 | 0% | **NOT POPULATED** |
| tags | 0 | 0% | **NOT POPULATED** |

*Technically 100% coverage but all values are "neutral" - no actual classification

---

### 5.2 Enrichment Opportunities

#### High Priority (Common Use Cases)

1. **Antonyms** (0% → target 80%+)
   - Could extract from GRE test prep materials
   - Could use AI classification (e.g., word2vec, BERT-based similarity)
   - Batch API like OpenAI embeddings API

2. **Roots/Morpheme Breakdown** (0% → target 60%+)
   - Could structure the existing mnemonics field
   - Could use ML to identify morpheme patterns
   - Could reference etymological databases

3. **Sentiment Classification** (0% actual → target 90%+)
   - Could use LLM classification (GPT, Claude, etc.)
   - Could train classifier on existing test scores
   - Could use existing sentiment lexicons

#### Medium Priority (Nice to Have)

4. **More Examples** (45% → target 80%+)
   - Could generate examples with LLM
   - Could scrape from dictionaries or test prep sites
   - Could add user-submitted examples

5. **Tags** (0% → target 50%+)
   - Semantic tags (emotion, abstract, physical, etc.)
   - Domain tags (technical, literary, colloquial, etc.)
   - Could be derived from definitions via NLP

#### Low Priority (Data Validation)

6. **Phonetic for wordbook entries** (79.6% → target 95%+)
   - Currently missing for ~2,670 words
   - Could use phonetic API or existing lexicons

---

## 6. PROCESSING DETAILS

### 6.1 Script: build_worddb.py

**Purpose**: Build primary rich word database from GRE_3 and frequency signals

**Execution**:
```bash
cd /Users/frankshi/Projects/app/erudite
uv run scripts/build_worddb.py
```

**Process Steps**:

1. **Load Phase** (Step 1/4):
   - Load GRE_3.json (6,515 words)
   - Load GRE_2.json (7,199 words, backup)
   - Load 再要你命3000.csv (3,033 words, frequency signal)
   - Load Magoosh.csv (1,008 words, frequency signal + examples)

2. **Build Phase** (Step 2/4):
   - For each GRE_3 word:
     - Parse definitions from `trans[]`
     - Parse synonyms from `syno[]`
     - Parse examples from `sentence[]`
     - Parse mnemonics from `remMethod`
     - Parse phonetics (prefer US)
     - Determine frequency tier via cross-reference
     - Supplement with Magoosh example if available
   - Output distribution:
     - Tier 1 (Core): 524 words
     - Tier 2 (Common): 1,750 words
     - Tier 3 (Advanced): 4,241 words

3. **Organization Phase** (Step 3/4):
   - Assign List/Unit indices (1-based)
   - Configuration:
     - 10 words per Unit
     - 10 Units per List
     - Result: ~65 Lists for 6,515 words

4. **Output Phase** (Step 4/4):
   - Write `words.json` (v2.0)
   - Location: `Erudite/Erudite/Resources/Data/words.json`
   - Size: ~5.6 MB
   - Includes metadata (version, word_count, structure)

---

### 6.2 Script: build_multibook.py

**Purpose**: Build multi-wordbook manifests and merge into unified word database

**Execution**:
```bash
cd /Users/frankshi/Projects/app/erudite
uv run scripts/build_multibook.py
```

**Book Processing Order**:

1. GRE 再要你命3000 (3,041 entries → 3,036 unique)
2. GRE 词以类记 (8,384 unique entries)
3. GRE 等价词 (827 unique entries)
4. TOEFL 核心 (4,264 unique entries)
5. TOEFL 词以类记 (3,669 unique entries)
6. SAT 核心 (4,463 unique entries)

**Process Steps**:

1. **Load Phase** (Step 1/3):
   - Load existing words.json (from build_worddb.py)
   - Index by spelling for quick lookup

2. **Process Each Book** (Step 2/3):
   - For each wordbook source:
     - Parse entries (name → spelling, trans → chinese)
     - Extract ordered word IDs
     - For words NOT in existing DB:
       - Create minimal entry with Chinese definition + phonetic
       - Add to new_words dict
     - Deduplicate while preserving order
     - Create book manifest entry

3. **Merge & Output** (Step 3/3):
   - Merge existing + new_words into all_words dict
   - Remove legacy listIndex/unitIndex from all words
   - Sort alphabetically by id
   - Write:
     - Updated `words.json` (v3.0) - 13,112 words
     - New `wordbooks.json` (v1.0) - 6 books
   - Size: ~7.5 MB

---

## 7. DATA DIRECTORY STRUCTURE

```
/Users/frankshi/Projects/app/erudite/
├── data/
│   ├── README.md
│   └── raw/
│       ├── GRE_3.json                                    (8.4 MB, 6515 words)
│       ├── GRE_2.json                                    (9.0 MB, 7199 words)
│       ├── L-GRE-再要你命3000.csv                        (176 KB, 3033 words)
│       ├── L-GRE-MagooshFlashcard.csv                    (208 KB, 1008 words)
│       ├── L-GRE-佛脚词表.csv                            (63 KB, ~2500 words)
│       ├── GRE3000_3_T.json                              (535 KB, 3041 words)
│       ├── gre-ciyileiji.json                            (962 KB, 8384 words)
│       ├── GRE_equivalent.json                           (62 KB, 827 words)
│       ├── TOEFL_3_T.json                                (814 KB, 4264 words)
│       ├── Categorized_TOEFL_Vocabulary_by_Zhanghongyan.json (766 KB, 3669 words)
│       └── SAT_3_T.json                                  (795 KB, 4463 words)
├── scripts/
│   ├── __init__.py
│   ├── build_worddb.py                                   (Main: GRE_3 → words.json v2.0)
│   └── build_multibook.py                                (Multi-book merger: → v3.0)
└── Erudite/Erudite/Resources/Data/
    ├── words.json                                        (Output: 13,112 words, 7.5 MB)
    └── wordbooks.json                                    (Output: 6 books manifest)
```

---

## 8. CURRENT STATE & GAPS

### 8.1 What's Currently Working

✅ **Fully Implemented**:
- GRE_3 parsing (definitions, examples, mnemonics, synonyms, phonetics)
- Frequency tiering (3-tier system based on cross-reference)
- Multiple word book integration
- Alphabetical sorting for clean diffs
- Phonetic standardization (US/UK variants)
- Example source attribution (dictionary/magoosh)

✅ **Well Covered**:
- Definitions (100%)
- Phonetics (79.6%)
- Examples (45%)
- Mnemonics (32.6%)
- Synonyms (45.6%)

---

### 8.2 What's Missing or Incomplete

❌ **Not Populated**:
- Antonyms (0%)
- Roots/Morpheme breakdowns (0%)
- Tags (0%)
- Sentiment differentiation (all "neutral")

⚠️ **Incomplete Coverage**:
- Examples: Only 45% of words have examples
- Synonyms: Only 45.6% have synonym groups
- Phonetics: ~20% missing (mostly wordbook entries)

---

### 8.3 Data Quality Issues

1. **POS Inconsistencies**: 
   - 3,791 definitions (28.9%) have empty `partOfSpeech`
   - Could be extracted from Chinese text

2. **Duplicate Words Across Books**:
   - Same word in multiple wordbooks
   - Deduplication preserves first occurrence

3. **Minimal Entries**:
   - 6,597 words from wordbooks lack rich data
   - Could be batch-enriched with API calls

---

## 9. RECOMMENDATIONS

### For Immediate Improvement

1. **Parse Existing Mnemonics into Roots**
   - Mnemonic field already contains morpheme breakdowns
   - Could regex-parse into `roots.segments[]` structure
   - Low effort, significant data enrichment

2. **Add Antonyms via External API**
   - Use WordNet or Merriam-Webster API
   - Batch process during build or separate enrichment step
   - Target: 80% coverage

3. **Classify Sentiment**
   - Use existing LLM API (OpenAI, Anthropic, etc.)
   - Or use lexicon-based approach (SentiWordNet)
   - Batch process during build

### For Medium-Term

4. **Enrich Wordbook Entries**
   - Batch API calls to enhance minimal entries
   - Could extract from dictionaries or test prep materials
   - Target: Fill examples, synonyms for common words

5. **Add Semantic Tags**
   - NLP classification based on definitions
   - Manual tags for test prep categories
   - User-defined tags support

6. **Complete Phonetics**
   - Fill missing ~2,670 phonetics
   - Use phonetic API or reference dictionary

### For Long-Term

7. **Machine Learning Enrichment**
   - Train classifier for sentiment/difficulty
   - Generate examples with LLM
   - Recommend related words

8. **Community Contributions**
   - User-submitted examples
   - Community-verified definitions
   - Crowdsourced phonetics for difficult words

---

## 10. KEY FILES REFERENCE

| Path | Purpose | Format | Size |
|------|---------|--------|------|
| `scripts/build_worddb.py` | Primary word DB builder | Python | 392 lines |
| `scripts/build_multibook.py` | Multi-book merger | Python | 219 lines |
| `data/raw/GRE_3.json` | Primary source | JSONL | 8.4 MB |
| `data/raw/L-GRE-再要你命3000.csv` | Frequency signal | CSV | 176 KB |
| `data/raw/L-GRE-MagooshFlashcard.csv` | Frequency signal + examples | CSV | 208 KB |
| `Erudite/Erudite/Models/Word.swift` | Swift data model | Swift | 108 lines |
| `Erudite/Erudite/Services/WordLoader.swift` | JSON deserializer | Swift | 126 lines |
| `Erudite/Erudite/Resources/Data/words.json` | Output: word database | JSON | 7.5 MB |
| `Erudite/Erudite/Resources/Data/wordbooks.json` | Output: book manifests | JSON | ~50 KB |

---

## 11. APPENDIX: CODE SAMPLES

### A. Frequency Tier Determination

```python
def determine_frequency(word: str, zyy_words: set[str], magoosh_words: set[str]) -> int:
    """
    Tier 1 (Core): in BOTH Magoosh AND 再要你命3000
    Tier 2 (Common): in 再要你命3000 only
    Tier 3 (Advanced): neither
    """
    in_zyy = word in zyy_words
    in_magoosh = word in magoosh_words
    if in_zyy and in_magoosh:
        return 1  # core (~600 words)
    elif in_zyy:
        return 2  # common (~2400 words)
    else:
        return 3  # advanced (~3500 words)
```

### B. Definition Parsing

```python
def parse_definitions(content: dict) -> list[Definition]:
    defs = []
    for t in content.get("trans", []):
        pos = t.get("pos", "").strip()
        english = t.get("tranOther", "").strip()
        chinese = t.get("tranCn", "").strip()
        if chinese or english:
            defs.append(Definition(
                partOfSpeech=pos,
                english=english,
                chinese=chinese,
            ))
    return defs
```

### C. JSON Deserialization (Swift)

```swift
struct WordDatabase: Codable {
    let version: String
    let generatedAt: String
    let wordCount: Int
    let words: [Word]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case wordCount = "word_count"
        case words
    }
}
```

---

**END OF ANALYSIS**
