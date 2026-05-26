"""
Build Erudite multi-wordbook manifest from qwerty-learner + existing data.

Strategy:
  1. Load our existing rich words.json (GRE_3 enriched) as the primary word store
  2. For each word book source, extract word IDs in order
  3. Words not in our DB get minimal entries (spelling + Chinese from source)
  4. Output wordbooks.json (manifest) + updated words.json (merged word store)

Word merging: existing rich data is NEVER overwritten.
"""

import json
from pathlib import Path
from typing import Optional


# === Config ===

PROJECT_ROOT = Path(__file__).parent.parent
DATA_RAW = PROJECT_ROOT / "data" / "raw"
OUTPUT_DIR = PROJECT_ROOT / "Erudite" / "Erudite" / "Resources" / "Data"
EXISTING_WORDS_PATH = OUTPUT_DIR / "words.json"

# Book definitions: (source_file, id, name, exam, structure)
BOOK_DEFS = [
    ("GRE3000_3_T.json", "gre-3000", "GRE 再要你命3000", "GRE", "sequential"),
    ("gre-ciyileiji.json", "gre-ciyileiji", "GRE 词以类记", "GRE", "thematic"),
    ("GRE_equivalent.json", "gre-equivalent", "GRE 等价词", "GRE", "sequential"),
    ("TOEFL_3_T.json", "toefl-core", "TOEFL 核心", "TOEFL", "sequential"),
    ("Categorized_TOEFL_Vocabulary_by_Zhanghongyan.json", "toefl-ciyileiji", "TOEFL 词以类记", "TOEFL", "thematic"),
    ("SAT_3_T.json", "sat-core", "SAT 核心", "SAT", "sequential"),
]


def load_existing_words() -> dict[str, dict]:
    """Load existing rich word database (keyed by spelling)."""
    if not EXISTING_WORDS_PATH.exists():
        print("  ⚠️  No existing words.json found, starting fresh")
        return {}
    with open(EXISTING_WORDS_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return {w["id"]: w for w in data["words"]}


def parse_qwerty_entry(entry: dict) -> tuple[str, Optional[str], Optional[str]]:
    """Parse a qwerty-learner word entry → (spelling, chinese_def, phonetic)."""
    spelling = entry["name"].lower().strip()
    trans = entry.get("trans", [])

    # Extract Chinese definition
    chinese = None
    for t in trans:
        # Skip category markers like "1.1", "1.2"
        if t and not (len(t) < 6 and "." in t and t.replace(".", "").isdigit()):
            chinese = t
            break

    # Extract phonetic
    phonetic = None
    if "usphone" in entry and entry["usphone"]:
        phonetic = f"/{entry['usphone']}/"
    elif "ukphone" in entry and entry["ukphone"]:
        phonetic = f"/{entry['ukphone']}/"

    return spelling, chinese, phonetic


def create_minimal_word(spelling: str, chinese: Optional[str], phonetic: Optional[str]) -> dict:
    """Create a minimal Word entry for words not in our existing DB."""
    definitions = []
    if chinese:
        # Parse POS from Chinese definition if present
        pos = ""
        cn = chinese
        for prefix in ["n．", "v．", "adj．", "adv．", "n. ", "v. ", "adj. ", "adv. ",
                       "vt．", "vi．", "vt. ", "vi. "]:
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


def process_book(
    source_file: str,
    book_id: str,
    existing_words: dict[str, dict],
    new_words: dict[str, dict],
) -> list[str]:
    """Process a book source and return ordered word IDs."""
    path = DATA_RAW / source_file
    with open(path, "r", encoding="utf-8") as f:
        entries = json.load(f)

    word_ids = []
    for entry in entries:
        spelling, chinese, phonetic = parse_qwerty_entry(entry)
        if not spelling:
            continue

        word_ids.append(spelling)

        # Only create new word if not already in existing or new_words
        if spelling not in existing_words and spelling not in new_words:
            new_words[spelling] = create_minimal_word(spelling, chinese, phonetic)

    return word_ids


def main():
    print("=== Erudite Multi-WordBook Builder ===\n")

    # Step 1: Load existing word database
    print("[1/3] Loading existing word database...")
    existing_words = load_existing_words()
    print(f"  Existing: {len(existing_words)} rich words")
    print()

    # Step 2: Process each book
    print("[2/3] Processing word books...")
    new_words: dict[str, dict] = {}
    books_manifest = []

    for source_file, book_id, name, exam, structure in BOOK_DEFS:
        word_ids = process_book(source_file, book_id, existing_words, new_words)
        # Deduplicate while preserving order
        seen = set()
        unique_ids = []
        for wid in word_ids:
            if wid not in seen:
                seen.add(wid)
                unique_ids.append(wid)

        books_manifest.append({
            "id": book_id,
            "name": name,
            "exam": exam,
            "source": "qwerty-learner",
            "structure": structure,
            "wordCount": len(unique_ids),
            "words": unique_ids,
        })

        in_existing = sum(1 for w in unique_ids if w in existing_words)
        print(f"  [{exam}] {name}: {len(unique_ids)} words ({in_existing} rich, {len(unique_ids) - in_existing} minimal)")

    print(f"\n  New words created: {len(new_words)}")
    print()

    # Step 3: Merge and output
    print("[3/3] Writing output files...")

    # Merge new words into the word database
    all_words = dict(existing_words)
    all_words.update(new_words)

    # Strip legacy listIndex/unitIndex from existing words
    for word in all_words.values():
        word.pop("listIndex", None)
        word.pop("unitIndex", None)

    # Rebuild words.json with merged data (sorted alphabetically for clean git diffs)
    words_output = {
        "version": "3.0",
        "generated_at": "2026-05-26",
        "word_count": len(all_words),
        "words": sorted(all_words.values(), key=lambda w: w["id"]),
    }

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    words_path = OUTPUT_DIR / "words.json"
    with open(words_path, "w", encoding="utf-8") as f:
        json.dump(words_output, f, ensure_ascii=False, indent=2)
    words_mb = words_path.stat().st_size / (1024 * 1024)
    print(f"  words.json: {len(all_words)} words ({words_mb:.1f} MB)")

    # Write wordbooks manifest
    manifest = {
        "version": "1.0",
        "generated_at": "2026-05-26",
        "books": books_manifest,
    }

    manifest_path = OUTPUT_DIR / "wordbooks.json"
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"  wordbooks.json: {len(books_manifest)} books")

    # Summary
    print(f"\n✅ Done!")
    print(f"  Total unique words: {len(all_words)}")
    print(f"  Word books: {len(books_manifest)}")
    for b in books_manifest:
        print(f"    [{b['exam']}] {b['name']}: {b['wordCount']} words")


if __name__ == "__main__":
    main()
