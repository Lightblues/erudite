#!/usr/bin/env python3
"""
Test script: Enrich words using ECDICT data.

Takes 10 sample words from our existing words.json that are missing data,
and fills in fields from ECDICT (phonetic, frequency, english definitions).

Usage: uv run scripts/test_enrich_ecdict.py
"""

import json
import csv
import os

ECDICT_PATH = "/Users/frankshi/Projects/_inbox/repo/ECDICT/ecdict.csv"
WORDS_PATH = "Erudite/Erudite/Resources/Data/words.json"

# Find 10 words that are sparse (from wordbook entries without english defs)
def find_sparse_words():
    with open(WORDS_PATH, encoding="utf-8") as f:
        data = json.load(f)

    sparse = []
    for w in data["words"]:
        # Sparse = no english definition, or no phonetic
        has_english = any(d.get("english") for d in w.get("definitions", []))
        if not has_english or not w.get("phonetic"):
            sparse.append(w)
        if len(sparse) >= 10:
            break
    return sparse


def load_ecdict_for_words(target_spellings: set):
    """Load ECDICT entries for specific words."""
    results = {}
    with open(ECDICT_PATH, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            w = row["word"].lower()
            if w in target_spellings and w not in results:
                results[w] = row
            if len(results) == len(target_spellings):
                break
    return results


def enrich_word(word: dict, ecdict_entry: dict) -> dict:
    """Enrich a word dict with ECDICT data."""
    enriched = word.copy()

    # Fill phonetic if missing
    if not enriched.get("phonetic") and ecdict_entry.get("phonetic"):
        enriched["phonetic"] = f"/{ecdict_entry['phonetic']}/"

    # Fill english definitions if missing
    has_english = any(d.get("english") for d in enriched.get("definitions", []))
    if not has_english and ecdict_entry.get("definition"):
        # ECDICT definitions are like "a. xxx\nn. yyy"
        ec_defs = ecdict_entry["definition"].split("\\n")
        for i, d in enumerate(enriched.get("definitions", [])):
            if i < len(ec_defs) and not d.get("english"):
                enriched["definitions"][i]["english"] = ec_defs[i].strip()

    # Add frequency metadata to tags
    bnc = ecdict_entry.get("bnc", "0")
    frq = ecdict_entry.get("frq", "0")
    collins = ecdict_entry.get("collins", "")
    if bnc != "0" or frq != "0":
        tags = enriched.get("tags", [])
        if bnc != "0":
            tags.append(f"bnc:{bnc}")
        if frq != "0":
            tags.append(f"coca:{frq}")
        if collins:
            tags.append(f"collins:{collins}")
        enriched["tags"] = tags

    return enriched


def main():
    print("=== ECDICT Enrichment Test ===\n")

    print("Finding sparse words...")
    sparse = find_sparse_words()
    print(f"Found {len(sparse)} sparse words\n")

    spellings = {w["spelling"].lower() for w in sparse}
    print(f"Loading ECDICT for: {', '.join(sorted(spellings)[:10])}")
    ecdict = load_ecdict_for_words(spellings)
    print(f"Matched {len(ecdict)}/{len(spellings)} in ECDICT\n")

    print("=" * 60)
    for word in sparse:
        sp = word["spelling"].lower()
        ec = ecdict.get(sp)
        if not ec:
            print(f"\n❌ {sp} — not in ECDICT")
            continue

        enriched = enrich_word(word, ec)

        print(f"\n✅ {sp}")
        print(f"   BEFORE: phonetic={word.get('phonetic', '∅')}")
        print(f"           defs={[d.get('english','')[:40] for d in word.get('definitions',[])]}")
        print(f"   AFTER:  phonetic={enriched.get('phonetic', '∅')}")
        print(f"           defs={[d.get('english','')[:40] for d in enriched.get('definitions',[])]}")
        print(f"           tags={enriched.get('tags', [])}")
        print(f"   ECDICT: cn={ec.get('translation','')[:60]}")

    print("\n" + "=" * 60)
    print(f"\nDone. {len(ecdict)} words enriched from ECDICT.")


if __name__ == "__main__":
    main()
