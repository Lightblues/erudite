#!/usr/bin/env python3
"""
Enrich words.json with ECDICT data.

Fills in:
- Missing phonetics
- BNC/COCA frequency ranks (as tags)
- Collins star rating
- Oxford 3000 flag
- Exam tags (gre/toefl/ielts/cet4/cet6)
- English definitions for sparse wordbook entries

Usage: uv run scripts/enrich_ecdict.py
"""

import json
import csv
import os
import sys
from pathlib import Path

ECDICT_PATH = "/Users/frankshi/Projects/_inbox/repo/ECDICT/ecdict.csv"
WORDS_PATH = Path("Erudite/Erudite/Resources/Data/words.json")


def write_words_json(path: Path, data: dict):
    """Write words.json in one-word-per-line format (valid JSON, git-friendly)."""
    words = data["words"]
    # Sort alphabetically for stable diffs
    words.sort(key=lambda w: w.get("spelling", "").lower())
    data["word_count"] = len(words)

    with open(path, "w", encoding="utf-8") as f:
        # Write header
        header = {k: v for k, v in data.items() if k != "words"}
        header_json = json.dumps(header, ensure_ascii=False)
        # Remove closing brace, we'll add "words" manually
        f.write("{\n")
        for k, v in header.items():
            f.write(f'"{k}":{json.dumps(v, ensure_ascii=False)},\n')
        f.write('"words":[\n')

        # Write each word as a compact single line
        for i, word in enumerate(words):
            line = json.dumps(word, ensure_ascii=False, separators=(",", ":"))
            if i < len(words) - 1:
                f.write(line + ",\n")
            else:
                f.write(line + "\n")

        f.write("]\n}\n")

    file_size = path.stat().st_size / (1024 * 1024)
    print(f"  Done. File size: {file_size:.1f} MB ({len(words):,} words)")


def load_ecdict_index():
    """Load full ECDICT into a dict keyed by lowercase word."""
    print("Loading ECDICT (770K entries)...", end=" ", flush=True)
    index = {}
    with open(ECDICT_PATH, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            w = row["word"].lower().strip()
            if w and w not in index:  # keep first occurrence
                index[w] = row
    print(f"done. {len(index):,} unique words loaded.")
    return index


def enrich_word(word: dict, ec: dict) -> tuple[dict, list[str]]:
    """
    Enrich a word dict with ECDICT data.
    Returns (enriched_word, list_of_changes_made).
    """
    changes = []
    enriched = word.copy()
    enriched["definitions"] = [d.copy() for d in word.get("definitions", [])]
    enriched["tags"] = list(word.get("tags", []))

    # 1. Fill missing phonetic
    if not enriched.get("phonetic") and ec.get("phonetic"):
        enriched["phonetic"] = f"/{ec['phonetic']}/"
        changes.append("phonetic")

    # 2. Fill missing english definitions (for sparse wordbook entries)
    has_english = any(d.get("english") for d in enriched.get("definitions", []))
    if not has_english and ec.get("definition"):
        # Parse ECDICT format: "a. xxx\nn. yyy" or "s. xxx\nv. yyy"
        ec_def_text = ec["definition"].replace("\\n", "\n")
        ec_defs = [d.strip() for d in ec_def_text.split("\n") if d.strip()]

        # Try to match by POS, or just fill first available
        for i, d in enumerate(enriched.get("definitions", [])):
            if not d.get("english") and i < len(ec_defs):
                # Remove POS prefix if present (e.g., "a. " or "n. ")
                def_text = ec_defs[i]
                if len(def_text) > 2 and def_text[1] in ".)" and def_text[0] in "asnvr":
                    def_text = def_text[2:].strip()
                enriched["definitions"][i]["english"] = def_text
                changes.append("english_def")

    # 3. Add frequency/metadata tags (avoid duplicates)
    existing_tags = set(enriched["tags"])

    bnc = ec.get("bnc", "0") or "0"
    frq = ec.get("frq", "0") or "0"
    collins = ec.get("collins", "") or ""
    oxford = ec.get("oxford", "") or ""
    exam_tag = ec.get("tag", "") or ""

    if bnc != "0" and f"bnc:{bnc}" not in existing_tags:
        enriched["tags"].append(f"bnc:{bnc}")
        changes.append("bnc")

    if frq != "0" and f"coca:{frq}" not in existing_tags:
        enriched["tags"].append(f"coca:{frq}")
        changes.append("coca")

    if collins and f"collins:{collins}" not in existing_tags:
        enriched["tags"].append(f"collins:{collins}")
        changes.append("collins")

    if oxford == "1" and "oxford3000" not in existing_tags:
        enriched["tags"].append("oxford3000")
        changes.append("oxford3000")

    # Exam tags
    if exam_tag:
        for t in exam_tag.strip().split():
            tag = t.lower()
            if tag and tag not in existing_tags:
                enriched["tags"].append(tag)
                changes.append(f"exam:{tag}")

    return enriched, changes


def main():
    print("=" * 60)
    print("ECDICT Enrichment Pipeline")
    print("=" * 60)

    # Load words.json
    print(f"\nLoading {WORDS_PATH}...")
    with open(WORDS_PATH, encoding="utf-8") as f:
        data = json.load(f)
    words = data["words"]
    print(f"  {len(words):,} words loaded.")

    # Load ECDICT
    ecdict = load_ecdict_index()

    # Enrich
    print("\nEnriching...")
    stats = {
        "total": len(words),
        "matched": 0,
        "phonetic_filled": 0,
        "english_def_filled": 0,
        "frequency_added": 0,
        "exam_tags_added": 0,
    }

    enriched_words = []
    for word in words:
        spelling = word["spelling"].lower()
        ec = ecdict.get(spelling)

        if ec:
            stats["matched"] += 1
            enriched, changes = enrich_word(word, ec)
            enriched_words.append(enriched)

            if "phonetic" in changes:
                stats["phonetic_filled"] += 1
            if "english_def" in changes:
                stats["english_def_filled"] += 1
            if "bnc" in changes or "coca" in changes:
                stats["frequency_added"] += 1
            if any(c.startswith("exam:") for c in changes):
                stats["exam_tags_added"] += 1
        else:
            enriched_words.append(word)

    # Write back (one-word-per-line format for git-friendly diffs)
    data["words"] = enriched_words
    data["enriched_with"] = "ecdict"
    data["enriched_at"] = "2026-05-28"

    print(f"\nWriting {WORDS_PATH} (one-word-per-line format)...")
    write_words_json(WORDS_PATH, data)

    # Report
    print("\n" + "=" * 60)
    print("Results:")
    print(f"  Total words:          {stats['total']:,}")
    print(f"  Matched in ECDICT:    {stats['matched']:,} ({stats['matched']*100//stats['total']}%)")
    print(f"  Phonetics filled:     {stats['phonetic_filled']:,}")
    print(f"  English defs filled:  {stats['english_def_filled']:,}")
    print(f"  Frequency added:      {stats['frequency_added']:,}")
    print(f"  Exam tags added:      {stats['exam_tags_added']:,}")
    print("=" * 60)


if __name__ == "__main__":
    main()
