"""
Build Erudite word database from multiple GRE vocabulary sources.

Strategy:
  1. GRE_3.json (新东方, 6515 words) as primary data source (richest fields)
  2. 再要你命3000.csv + Magoosh.csv as frequency signals for tiering
  3. GRE_2.json as supplement for missing fields
  4. Organize into List/Unit structure for 打卡 experience

Frequency Tiers:
  - Core (tier 1): words in BOTH Magoosh AND 再要你命3000 (~600 words)
  - Common (tier 2): words in 再要你命3000 (not already core) (~2400 words)
  - Advanced (tier 3): remaining GRE_3 words

Output: words.json matching Erudite app schema
"""

import csv
import json
import sys
from pathlib import Path
from dataclasses import dataclass, field, asdict
from typing import Optional


# === Config ===

PROJECT_ROOT = Path(__file__).parent.parent
DATA_RAW = PROJECT_ROOT / "data" / "raw"
GRE3_PATH = DATA_RAW / "GRE_3.json"
GRE2_PATH = DATA_RAW / "GRE_2.json"
ZYY3000_PATH = DATA_RAW / "L-GRE-再要你命3000.csv"
MAGOOSH_PATH = DATA_RAW / "L-GRE-MagooshFlashcard.csv"

OUTPUT_PATH = PROJECT_ROOT / "Erudite/Erudite/Resources/Data/words.json"

# Unit/List structure config
WORDS_PER_UNIT = 10
UNITS_PER_LIST = 10


# === Data Classes (matching Erudite app schema) ===

@dataclass
class Definition:
    partOfSpeech: str
    english: str
    chinese: str


@dataclass
class Morpheme:
    text: str
    type: str  # prefix / root / suffix
    meaning: str


@dataclass
class MorphemeBreakdown:
    segments: list[Morpheme]
    logic: str


@dataclass
class Example:
    sentence: str
    source: str  # generated / official / custom


@dataclass
class Word:
    id: str
    spelling: str
    phonetic: Optional[str]
    definitions: list[Definition]
    roots: Optional[MorphemeBreakdown]
    synonymGroups: list[list[str]]
    antonyms: list[str]
    sentiment: str  # positive / negative / neutral
    frequency: int  # 1=core, 2=common, 3=advanced
    examples: list[Example]
    mnemonics: list[str]
    tags: list[str]
    # Extra fields for organization
    listIndex: Optional[int] = None  # which List (1-based)
    unitIndex: Optional[int] = None  # which Unit within list (1-based)


# === Loaders ===

def load_gre3() -> dict[str, dict]:
    """Load GRE_3.json (新东方) - primary source."""
    words = {}
    with open(GRE3_PATH, "r", encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            word = entry["headWord"].lower().strip()
            words[word] = entry["content"]["word"]["content"]
    print(f"  GRE_3: {len(words)} words loaded")
    return words


def load_gre2() -> dict[str, dict]:
    """Load GRE_2.json (有道) - supplement source."""
    words = {}
    with open(GRE2_PATH, "r", encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            word = entry["headWord"].lower().strip()
            words[word] = entry["content"]["word"]["content"]
    print(f"  GRE_2: {len(words)} words loaded")
    return words


def load_zyy3000() -> set[str]:
    """Load 再要你命3000 word list (frequency signal)."""
    words = set()
    with open(ZYY3000_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if row and row[0].strip():
                w = row[0].strip().lower().strip("﻿")
                # Skip list markers
                if w.startswith("list") or w.startswith("unit"):
                    continue
                words.add(w)
    print(f"  再要你命3000: {len(words)} words loaded")
    return words


def load_magoosh() -> dict[str, dict]:
    """Load Magoosh flashcards (frequency signal + English definitions)."""
    words = {}
    with open(MAGOOSH_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if row and row[0].strip():
                w = row[0].strip().lower()
                words[w] = {
                    "definition": row[1] if len(row) > 1 else "",
                    "example": row[2] if len(row) > 2 else "",
                }
    print(f"  Magoosh: {len(words)} words loaded")
    return words


# === Transformers ===

def determine_frequency(word: str, zyy_words: set[str], magoosh_words: set[str]) -> int:
    """Determine frequency tier based on cross-reference."""
    in_zyy = word in zyy_words
    in_magoosh = word in magoosh_words
    if in_zyy and in_magoosh:
        return 1  # core
    elif in_zyy:
        return 2  # common
    else:
        return 3  # advanced


def parse_definitions(content: dict) -> list[Definition]:
    """Parse definitions from GRE_3 format."""
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


def parse_synonyms(content: dict) -> list[list[str]]:
    """Parse synonym groups from GRE_3 format."""
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


def parse_examples(content: dict) -> list[Example]:
    """Parse example sentences from GRE_3 format."""
    examples = []
    sentence_data = content.get("sentence", {})
    if not sentence_data:
        return examples
    for s in sentence_data.get("sentences", []):
        text = s.get("sContent", "").strip()
        # Remove HTML bold tags
        text = text.replace("<b>", "").replace("</b>", "")
        if text:
            examples.append(Example(sentence=text, source="dictionary"))
    return examples


def parse_mnemonic(content: dict) -> list[str]:
    """Parse mnemonic from GRE_3 format."""
    rem = content.get("remMethod", {})
    if rem and rem.get("val"):
        return [rem["val"].strip()]
    return []


def parse_phonetic(content: dict) -> Optional[str]:
    """Parse phonetic from GRE_3 format."""
    # Prefer US pronunciation
    for key in ["usphone", "ukphone", "phone"]:
        if key in content and content[key]:
            ph = content[key].strip()
            if ph and not ph.startswith("/"):
                ph = f"/{ph}/"
            return ph
    return None


def build_word(
    spelling: str,
    content: dict,
    frequency: int,
    magoosh_data: Optional[dict] = None,
) -> Word:
    """Build a Word from GRE_3 content."""
    definitions = parse_definitions(content)
    synonyms = parse_synonyms(content)
    examples = parse_examples(content)
    mnemonics = parse_mnemonic(content)
    phonetic = parse_phonetic(content)

    # Supplement with Magoosh example if available and richer
    if magoosh_data and magoosh_data.get("example"):
        magoosh_example = magoosh_data["example"].strip()
        if magoosh_example and len(magoosh_example) > 20:
            examples.append(Example(sentence=magoosh_example, source="magoosh"))

    # Determine sentiment heuristic (basic - can be AI-enhanced later)
    sentiment = "neutral"

    return Word(
        id=spelling.lower(),
        spelling=spelling,
        phonetic=phonetic,
        definitions=definitions,
        roots=None,  # To be AI-enriched later
        synonymGroups=synonyms,
        antonyms=[],  # To be AI-enriched later
        sentiment=sentiment,
        frequency=frequency,
        examples=examples,
        mnemonics=mnemonics,
        tags=[],
    )


def assign_list_unit(words: list[Word]) -> list[Word]:
    """Assign List/Unit indices for 打卡 structure.

    Sort: core first, then common, then advanced.
    Within each tier, maintain original order (roughly by frequency).
    """
    # Group by tier
    by_tier = {1: [], 2: [], 3: []}
    for w in words:
        by_tier[w.frequency].append(w)

    # Assign list/unit sequentially
    ordered = by_tier[1] + by_tier[2] + by_tier[3]
    for i, word in enumerate(ordered):
        list_idx = i // (WORDS_PER_UNIT * UNITS_PER_LIST) + 1
        unit_within_list = (i % (WORDS_PER_UNIT * UNITS_PER_LIST)) // WORDS_PER_UNIT + 1
        word.listIndex = list_idx
        word.unitIndex = unit_within_list

    return ordered


# === Serialization ===

def word_to_dict(w: Word) -> dict:
    """Convert Word to JSON-serializable dict."""
    d = {
        "id": w.id,
        "spelling": w.spelling,
        "phonetic": w.phonetic,
        "frequency": w.frequency,
        "sentiment": w.sentiment,
        "definitions": [asdict(de) for de in w.definitions],
        "synonymGroups": w.synonymGroups,
        "antonyms": w.antonyms,
        "examples": [asdict(e) for e in w.examples],
        "mnemonics": w.mnemonics,
        "tags": w.tags,
        "listIndex": w.listIndex,
        "unitIndex": w.unitIndex,
    }
    if w.roots:
        d["roots"] = asdict(w.roots)
    else:
        d["roots"] = None
    return d


# === Main ===

def main():
    print("=== Erudite Word Database Builder ===\n")

    # Step 1: Load all sources
    print("[1/4] Loading sources...")
    gre3 = load_gre3()
    gre2 = load_gre2()
    zyy_words = load_zyy3000()
    magoosh = load_magoosh()
    print()

    # Step 2: Build words from GRE_3 with frequency tiering
    print("[2/4] Building words with frequency tiering...")
    words = []
    magoosh_keys = set(magoosh.keys())

    for spelling, content in gre3.items():
        freq = determine_frequency(spelling, zyy_words, magoosh_keys)
        magoosh_data = magoosh.get(spelling)
        word = build_word(spelling, content, freq, magoosh_data)
        words.append(word)

    # Stats
    tier_counts = {1: 0, 2: 0, 3: 0}
    for w in words:
        tier_counts[w.frequency] += 1
    print(f"  Core (tier 1): {tier_counts[1]} words")
    print(f"  Common (tier 2): {tier_counts[2]} words")
    print(f"  Advanced (tier 3): {tier_counts[3]} words")
    print(f"  Total: {len(words)} words")
    print()

    # Step 3: Assign List/Unit structure
    print("[3/4] Organizing into List/Unit structure...")
    words = assign_list_unit(words)
    total_lists = words[-1].listIndex if words else 0
    print(f"  {total_lists} Lists × {UNITS_PER_LIST} Units × {WORDS_PER_UNIT} words")
    print()

    # Step 4: Output
    print("[4/4] Writing output...")
    output = {
        "version": "2.0",
        "generated_at": "2026-05-26",
        "word_count": len(words),
        "structure": {
            "words_per_unit": WORDS_PER_UNIT,
            "units_per_list": UNITS_PER_LIST,
            "total_lists": total_lists,
        },
        "tiers": {
            "core": tier_counts[1],
            "common": tier_counts[2],
            "advanced": tier_counts[3],
        },
        "words": [word_to_dict(w) for w in words],
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    file_size_mb = OUTPUT_PATH.stat().st_size / (1024 * 1024)
    print(f"  Output: {OUTPUT_PATH}")
    print(f"  Size: {file_size_mb:.1f} MB")
    print(f"\n✅ Done! {len(words)} words built into {total_lists} lists.")

    # Sample output
    print("\n--- Sample (first 3 words) ---")
    for w in words[:3]:
        print(f"  [{w.listIndex}-{w.unitIndex}] {w.spelling} (tier {w.frequency})")
        if w.definitions:
            print(f"    {w.definitions[0].partOfSpeech}: {w.definitions[0].chinese}")
        if w.mnemonics:
            print(f"    💡 {w.mnemonics[0][:60]}")


if __name__ == "__main__":
    main()
