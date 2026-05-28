#!/usr/bin/env python3
"""
Merge AI enrichment results back into words.json.

Reads data/ai_enriched_words.jsonl and updates words.json with:
- Better Chinese definitions (if shorter/more concise)
- Mnemonics (if missing)
- Examples (if missing)
- Synonyms/Antonyms (supplements existing)

Usage: uv run scripts/merge_ai_enrichment.py
"""

import json
from pathlib import Path

WORDS_PATH = Path("Erudite/Erudite/Resources/Data/words.json")
ENRICHMENT_PATH = Path("data/ai_enriched_words.jsonl")


def write_words_json(path: Path, data: dict):
    """Write words.json in one-word-per-line format (valid JSON, git-friendly)."""
    words = data["words"]
    words.sort(key=lambda w: w.get("spelling", "").lower())
    data["word_count"] = len(words)

    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n")
        for k, v in data.items():
            if k == "words":
                continue
            f.write(f'"{k}":{json.dumps(v, ensure_ascii=False)},\n')
        f.write('"words":[\n')
        for i, word in enumerate(words):
            line = json.dumps(word, ensure_ascii=False, separators=(",", ":"))
            f.write(line + (",\n" if i < len(words) - 1 else "\n"))
        f.write("]\n}\n")

    size = path.stat().st_size / (1024 * 1024)
    print(f"  Written: {size:.1f} MB ({len(words):,} words)")


def merge_enrichment(word: dict, ai: dict) -> tuple[dict, list[str]]:
    """Merge AI enrichment into existing word. Returns (merged, changes)."""
    merged = word.copy()
    merged["definitions"] = [d.copy() for d in word.get("definitions", [])]
    merged["tags"] = list(word.get("tags", []))
    changes = []

    # 1. Mnemonics: add if missing
    if not merged.get("mnemonics") and ai.get("mnemonics"):
        merged["mnemonics"] = ai["mnemonics"]
        changes.append("mnemonic")

    # 2. Examples: add if missing
    if not merged.get("examples") and ai.get("examples"):
        examples = []
        for ex in ai["examples"][:2]:
            examples.append({
                "sentence": ex.get("sentence", ""),
                "source": ex.get("source", "AI"),
            })
        merged["examples"] = examples
        changes.append("examples")

    # 3. Synonyms: supplement if sparse
    existing_syns = set(s for group in merged.get("synonymGroups", []) for s in group)
    ai_syns = ai.get("synonyms", [])
    if ai_syns and len(existing_syns) < 3:
        new_syns = [s for s in ai_syns if s not in existing_syns]
        if new_syns:
            if merged.get("synonymGroups"):
                merged["synonymGroups"][0].extend(new_syns[:3])
            else:
                merged["synonymGroups"] = [new_syns[:5]]
            changes.append("synonyms")

    # 4. Antonyms: add if missing
    if not merged.get("antonyms") and ai.get("antonyms"):
        merged["antonyms"] = ai["antonyms"][:3]
        changes.append("antonyms")

    # 5. Definitions: improve Chinese if AI's is more concise
    ai_defs = ai.get("definitions", [])
    for i, d in enumerate(merged.get("definitions", [])):
        cn = d.get("chinese", "")
        # If existing CN is too verbose (>15 chars) and AI has a shorter one
        if len(cn) > 15 and i < len(ai_defs):
            ai_cn = ai_defs[i].get("cn", "")
            if ai_cn and len(ai_cn) <= 12:
                merged["definitions"][i]["chinese"] = ai_cn
                changes.append("concise_cn")
                break  # Only fix first verbose one

    # 6. Tag as AI-enriched
    if changes and "ai_enriched" not in merged["tags"]:
        merged["tags"].append("ai_enriched")

    return merged, changes


def main():
    print("=" * 60)
    print("Merge AI Enrichment → words.json")
    print("=" * 60)

    if not ENRICHMENT_PATH.exists():
        print(f"ERROR: {ENRICHMENT_PATH} not found. Run enrich_ai.py first.")
        return

    # Load enrichment data
    print(f"\nLoading {ENRICHMENT_PATH}...")
    enrichments = {}
    with open(ENRICHMENT_PATH, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                entry = json.loads(line)
                spelling = entry.get("spelling", "").lower()
                if spelling:
                    enrichments[spelling] = entry
    print(f"  {len(enrichments):,} enrichment entries loaded.")

    # Load words.json
    print(f"Loading {WORDS_PATH}...")
    with open(WORDS_PATH, encoding="utf-8") as f:
        data = json.load(f)
    words = data["words"]
    print(f"  {len(words):,} words loaded.")

    # Merge
    print("\nMerging...")
    stats = {"mnemonic": 0, "examples": 0, "synonyms": 0, "antonyms": 0, "concise_cn": 0}
    merged_count = 0

    for i, word in enumerate(words):
        spelling = word.get("spelling", "").lower()
        ai = enrichments.get(spelling)
        if ai:
            merged, changes = merge_enrichment(word, ai)
            if changes:
                words[i] = merged
                merged_count += 1
                for c in changes:
                    if c in stats:
                        stats[c] += 1

    # Write
    data["words"] = words
    print(f"\nWriting {WORDS_PATH}...")
    write_words_json(WORDS_PATH, data)

    # Report
    print("\n" + "=" * 60)
    print(f"Results: {merged_count:,} words updated")
    for k, v in stats.items():
        if v:
            print(f"  +{k}: {v:,}")
    print("=" * 60)


if __name__ == "__main__":
    main()
