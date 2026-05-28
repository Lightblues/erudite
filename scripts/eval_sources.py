#!/usr/bin/env python3
"""
Data source evaluation script for Erudite vocabulary app.

Generates side-by-side comparison of word entries from different sources
for a set of sample words, so we can visually compare quality.

Sources compared:
1. GRE_3 (新东方) — current primary, richest data
2. ECDICT — 770K words, bilingual, frequency data
3. MW Collegiate API — authoritative English definitions + etymology
4. Free Dictionary API — Wiktionary-based fallback

Output: scripts/data_eval/comparison.md
"""

import json
import csv
import asyncio
import urllib.request
import os
import sys

# Paths
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "raw")
ECDICT_PATH = "/Users/frankshi/Projects/_inbox/repo/ECDICT/ecdict.csv"
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "data_eval")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# MW API keys (from Config.json)
MW_DICT_KEY = "582650d6-aa0a-47ac-bf5e-7c0fa1290641"
MW_THES_KEY = "141b24f1-bc77-4a73-9d15-97eeea1059a7"

# Sample words: mix of GRE vocab + common words that appear in definitions
SAMPLE_WORDS = [
    # GRE core (should be in all sources)
    "ephemeral", "aberrant", "supplant", "belligerent", "laconic",
    "equivocate", "prodigal", "pristine", "tenacious", "pragmatic",
    # GRE advanced
    "pellucid", "recondite", "sycophant", "obsequious", "perfunctory",
    # Common words (likely clicked in definitions)
    "quiet", "pattern", "follow", "membrane", "consist",
    # TOEFL/SAT level
    "ambiguous", "comprehensive", "deteriorate", "inherent", "subsequent",
]


def load_gre3():
    """Load GRE_3.json entries for sample words."""
    results = {}
    path = os.path.join(DATA_DIR, "GRE_3.json")
    with open(path, encoding="utf-8") as f:
        for line in f:
            entry = json.loads(line)
            word = entry["headWord"].lower()
            if word in SAMPLE_WORDS:
                content = entry.get("content", {}).get("word", {}).get("content", {})
                trans = content.get("trans", [])
                cn = "; ".join(t.get("tranCn", "").strip() for t in trans if t.get("tranCn"))
                en = "; ".join(t.get("tranOther", "").strip() for t in trans if t.get("tranOther"))
                pos = ", ".join(t.get("pos", "") for t in trans if t.get("pos"))

                sentences = content.get("sentence", {}).get("sentences", [])
                example = sentences[0]["sContent"] if sentences else ""
                example_cn = sentences[0].get("sCn", "") if sentences else ""

                syno = content.get("syno", {}).get("synos", [])
                syn_text = "; ".join(
                    f'{s.get("pos","")} {s.get("tran","")}' for s in syno[:2]
                )

                mnemonic = content.get("remMethod", {}).get("val", "")
                phonetic = content.get("usphone", "") or content.get("ukphone", "")

                results[word] = {
                    "phonetic": phonetic,
                    "pos": pos,
                    "cn": cn,
                    "en": en[:150],
                    "example": example[:120],
                    "example_cn": example_cn[:80],
                    "synonyms": syn_text[:100],
                    "mnemonic": mnemonic[:100],
                }
    return results


def load_ecdict():
    """Load ECDICT entries for sample words."""
    results = {}
    with open(ECDICT_PATH, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            w = row["word"].lower()
            if w in SAMPLE_WORDS and w not in results:
                results[w] = {
                    "phonetic": row.get("phonetic", ""),
                    "cn": row.get("translation", "").replace("\\n", " | ")[:150],
                    "en": row.get("definition", "")[:150],
                    "collins": row.get("collins", ""),
                    "oxford": row.get("oxford", ""),
                    "tag": row.get("tag", ""),
                    "bnc": row.get("bnc", ""),
                    "frq": row.get("frq", ""),
                }
    return results


def fetch_mw(word):
    """Fetch MW Collegiate API for a word."""
    url = f"https://dictionaryapi.com/api/v3/references/collegiate/json/{word}?key={MW_DICT_KEY}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
            if not data or not isinstance(data[0], dict):
                return None
            entry = data[0]
            # Parse definitions
            defs = []
            fl = entry.get("fl", "")
            for d in entry.get("def", []):
                for sseq in d.get("sseq", []):
                    for item in sseq:
                        if isinstance(item, list) and len(item) >= 2 and item[0] == "sense":
                            sense = item[1]
                            for dt in sense.get("dt", []):
                                if dt[0] == "text":
                                    text = dt[1].replace("{bc}", "").replace("{it}", "").replace("{/it}", "")
                                    text = text.replace("{wi}", "").replace("{/wi}", "").strip()
                                    defs.append(text)
            # Etymology
            etym = ""
            for et in entry.get("et", []):
                if isinstance(et, list) and len(et) >= 2 and et[0] == "text":
                    etym = et[1].replace("{it}", "").replace("{/it}", "").strip()
            # Phonetic
            phonetic = ""
            hwi = entry.get("hwi", {})
            prs = hwi.get("prs", [])
            if prs:
                phonetic = prs[0].get("mw", "")

            return {
                "phonetic": phonetic,
                "pos": fl,
                "defs": defs[:4],
                "etymology": etym[:150],
            }
    except Exception as e:
        print(f"  [MW] Error for '{word}': {e}")
        return None


def fetch_free_dict(word):
    """Fetch Free Dictionary API for a word."""
    url = f"https://api.dictionaryapi.dev/api/v2/entries/en/{word}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
            if not data:
                return None
            entry = data[0]
            phonetic = entry.get("phonetic", "")
            defs = []
            synonyms = []
            for meaning in entry.get("meanings", []):
                pos = meaning.get("partOfSpeech", "")
                for syn in meaning.get("synonyms", [])[:3]:
                    synonyms.append(syn)
                for d in meaning.get("definitions", [])[:2]:
                    defs.append(f"({pos}) {d['definition']}")
            return {
                "phonetic": phonetic,
                "defs": defs[:4],
                "synonyms": ", ".join(synonyms[:6]),
            }
    except Exception as e:
        print(f"  [FreeDict] Error for '{word}': {e}")
        return None


def main():
    print("Loading GRE_3...")
    gre3 = load_gre3()
    print(f"  Found {len(gre3)}/{len(SAMPLE_WORDS)} words")

    print("Loading ECDICT...")
    ecdict = load_ecdict()
    print(f"  Found {len(ecdict)}/{len(SAMPLE_WORDS)} words")

    print("Fetching MW API (25 words, ~5 seconds)...")
    mw = {}
    for w in SAMPLE_WORDS:
        print(f"  {w}...", end=" ")
        result = fetch_mw(w)
        if result:
            mw[w] = result
            print("✓")
        else:
            print("✗")

    print("Fetching Free Dictionary API...")
    free_dict = {}
    for w in SAMPLE_WORDS:
        print(f"  {w}...", end=" ")
        result = fetch_free_dict(w)
        if result:
            free_dict[w] = result
            print("✓")
        else:
            print("✗")

    # Generate comparison markdown
    output_path = os.path.join(OUTPUT_DIR, "comparison.md")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("# Data Source Comparison\n\n")
        f.write("Generated for Erudite vocabulary app data pipeline evaluation.\n\n")
        f.write("---\n\n")

        for word in SAMPLE_WORDS:
            f.write(f"## {word}\n\n")

            # GRE_3
            g = gre3.get(word)
            f.write("### Source 1: GRE_3 (新东方)\n\n")
            if g:
                f.write(f"- **音标**: /{g['phonetic']}/\n")
                f.write(f"- **词性**: {g['pos']}\n")
                f.write(f"- **中文**: {g['cn']}\n")
                f.write(f"- **英文**: {g['en']}\n")
                f.write(f"- **例句**: {g['example']}\n")
                f.write(f"- **例句译**: {g['example_cn']}\n")
                f.write(f"- **同义词**: {g['synonyms']}\n")
                f.write(f"- **助记**: {g['mnemonic']}\n")
            else:
                f.write("*Not in GRE_3*\n")
            f.write("\n")

            # ECDICT
            e = ecdict.get(word)
            f.write("### Source 2: ECDICT\n\n")
            if e:
                f.write(f"- **音标**: {e['phonetic']}\n")
                f.write(f"- **中文**: {e['cn']}\n")
                f.write(f"- **英文**: {e['en']}\n")
                f.write(f"- **柯林斯**: {e['collins']}星  **牛津3000**: {'✓' if e['oxford']=='1' else '✗'}\n")
                f.write(f"- **标签**: {e['tag']}\n")
                f.write(f"- **BNC频率**: {e['bnc']}  **COCA频率**: {e['frq']}\n")
            else:
                f.write("*Not in ECDICT*\n")
            f.write("\n")

            # MW
            m = mw.get(word)
            f.write("### Source 3: Merriam-Webster API\n\n")
            if m:
                f.write(f"- **音标**: {m['phonetic']}\n")
                f.write(f"- **词性**: {m['pos']}\n")
                f.write(f"- **释义**:\n")
                for i, d in enumerate(m["defs"], 1):
                    f.write(f"  {i}. {d}\n")
                if m["etymology"]:
                    f.write(f"- **词源**: {m['etymology']}\n")
            else:
                f.write("*Not found in MW*\n")
            f.write("\n")

            # Free Dictionary
            fd = free_dict.get(word)
            f.write("### Source 4: Free Dictionary API\n\n")
            if fd:
                f.write(f"- **音标**: {fd['phonetic']}\n")
                f.write(f"- **释义**:\n")
                for i, d in enumerate(fd["defs"], 1):
                    f.write(f"  {i}. {d}\n")
                if fd["synonyms"]:
                    f.write(f"- **同义词**: {fd['synonyms']}\n")
            else:
                f.write("*Not found*\n")
            f.write("\n---\n\n")

    print(f"\n✅ Comparison written to: {output_path}")
    print(f"   {len(SAMPLE_WORDS)} words × 4 sources")


if __name__ == "__main__":
    main()
