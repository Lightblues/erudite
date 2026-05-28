#!/usr/bin/env python3
"""
AI Batch Enrichment for Erudite words.

Enriches words with AI-generated content:
- Concise Chinese definitions (for memorization)
- Simple English definitions
- Example sentences with Chinese translation
- Word root mnemonics (Chinese learner perspective)
- Synonyms & Antonyms

Features:
- 10 concurrent requests (configurable)
- Checkpoint file for resume after interruption
- Priority: Tier1 → Tier2 → Tier3
- Skips words already enriched

Usage:
  uv run scripts/enrich_ai.py              # Run full enrichment
  uv run scripts/enrich_ai.py --limit 50   # Process only 50 words
  uv run scripts/enrich_ai.py --tier 1     # Only Tier 1 words
  uv run scripts/enrich_ai.py --reset      # Clear checkpoint, start over

Config: .env file (ENRICH_API_URL, ENRICH_API_KEY, ENRICH_MODEL)
"""

import json
import asyncio
import argparse
import os
import sys
import time
from pathlib import Path
from dotenv import load_dotenv
from openai import AsyncOpenAI

# Load .env
load_dotenv()

API_URL = os.environ.get("ENRICH_API_URL", "http://localhost:33001")
API_KEY = os.environ.get("ENRICH_API_KEY", "")
MODEL = os.environ.get("ENRICH_MODEL", "")
CONCURRENCY = int(os.environ.get("ENRICH_CONCURRENCY", "10"))

WORDS_PATH = Path("Erudite/Erudite/Resources/Data/words.json")
CHECKPOINT_PATH = Path("data/ai_enrichment_checkpoint.json")
OUTPUT_PATH = Path("data/ai_enriched_words.jsonl")

SYSTEM_PROMPT = """You are a vocabulary enrichment assistant for a GRE/TOEFL vocabulary learning app targeting Chinese-speaking learners.

For each word, generate structured data in JSON. Guidelines:
1. Chinese definitions: CONCISE (≤10 chars per sense), suitable for flash-card quick recall
2. English definitions: Simple, 1 sentence, avoid circular definitions
3. Example: Natural sentence showing common usage context
4. Mnemonic: Word root breakdown connecting to meaning (in Chinese). Use format like "ab(离开) + err(走偏) → 异常的"
5. Synonyms: 3-5 most useful, GRE-level preferred
6. Antonyms: 1-3 if applicable

Output ONLY valid JSON. No markdown fences, no extra text."""

USER_PROMPT_TEMPLATE = """Word: "{word}"
Known info: {known_info}

Return JSON:
{{
  "definitions": [{{"pos": "adj/n/v/adv", "en": "<1-sentence English def>", "cn": "<concise Chinese ≤10 chars>"}}],
  "examples": [{{"sentence": "<natural English sentence>", "translation": "<Chinese translation>"}}],
  "mnemonics": ["<word root/association breakdown in Chinese>"],
  "synonyms": ["word1", "word2", "word3"],
  "antonyms": ["word1", "word2"]
}}"""


def load_words():
    """Load words.json, return sorted by priority (tier 1 first)."""
    with open(WORDS_PATH, encoding="utf-8") as f:
        data = json.load(f)
    return data


def load_checkpoint() -> set:
    """Load set of already-processed word IDs."""
    if CHECKPOINT_PATH.exists():
        with open(CHECKPOINT_PATH, encoding="utf-8") as f:
            return set(json.load(f))
    return set()


def save_checkpoint(processed: set):
    """Save checkpoint."""
    CHECKPOINT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CHECKPOINT_PATH, "w", encoding="utf-8") as f:
        json.dump(sorted(processed), f)


def needs_enrichment(word: dict) -> bool:
    """Check if a word needs AI enrichment."""
    # Skip if already has AI-generated mnemonic AND good definitions
    has_mnemonic = bool(word.get("mnemonics"))
    has_example = bool(word.get("examples"))
    defs = word.get("definitions", [])
    has_good_cn = any(d.get("chinese") and len(d["chinese"]) <= 15 for d in defs)

    # Need enrichment if missing key fields
    return not (has_mnemonic and has_example and has_good_cn)


def build_prompt(word: dict) -> str:
    """Build the user prompt for a word."""
    spelling = word["spelling"]
    known_parts = []
    for d in word.get("definitions", []):
        cn = d.get("chinese", "")
        en = d.get("english", "")
        pos = d.get("partOfSpeech", "")
        if cn:
            known_parts.append(f"[{pos}] CN: {cn}")
        if en:
            known_parts.append(f"[{pos}] EN: {en[:80]}")

    known_info = "; ".join(known_parts[:3]) if known_parts else "(no existing data)"
    return USER_PROMPT_TEMPLATE.format(word=spelling, known_info=known_info)


async def enrich_one(client: AsyncOpenAI, word: dict, semaphore: asyncio.Semaphore) -> tuple[str, dict | None]:
    """Enrich a single word via AI API."""
    async with semaphore:
        spelling = word["spelling"]
        user_msg = build_prompt(word)

        try:
            # Streaming call
            stream = await client.chat.completions.create(
                model=MODEL,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_msg},
                ],
                stream=True,
                temperature=0.3,
                max_tokens=600,
            )

            full_response = ""
            async for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    full_response += chunk.choices[0].delta.content

            # Parse JSON
            text = full_response.strip()
            if text.startswith("```"):
                text = text.split("\n", 1)[1]
                if text.endswith("```"):
                    text = text[:-3]
            text = text.strip()

            result = json.loads(text)
            result["spelling"] = spelling
            return spelling, result

        except json.JSONDecodeError:
            print(f"  ⚠️  {spelling}: JSON parse error")
            return spelling, None
        except Exception as e:
            print(f"  ⚠️  {spelling}: {str(e)[:60]}")
            return spelling, None


async def main():
    parser = argparse.ArgumentParser(description="AI batch enrichment for Erudite words")
    parser.add_argument("--limit", type=int, default=0, help="Max words to process (0=all)")
    parser.add_argument("--tier", type=int, default=0, help="Only process specific tier (1/2/3)")
    parser.add_argument("--concurrency", type=int, default=CONCURRENCY, help="Concurrent requests")
    parser.add_argument("--reset", action="store_true", help="Clear checkpoint and start over")
    args = parser.parse_args()

    if args.reset and CHECKPOINT_PATH.exists():
        CHECKPOINT_PATH.unlink()
        print("Checkpoint cleared.")

    print("=" * 60)
    print("AI Batch Enrichment")
    print(f"  API: {API_URL}")
    print(f"  Model: {MODEL}")
    print(f"  Concurrency: {args.concurrency}")
    print("=" * 60)

    if not API_KEY:
        print("ERROR: ENRICH_API_KEY not set in .env")
        sys.exit(1)

    # Load data
    data = load_words()
    words = data["words"]
    processed = load_checkpoint()
    print(f"\nTotal words: {len(words):,}")
    print(f"Already processed: {len(processed):,}")

    # Filter: by tier, needs enrichment, not already processed
    TIER_MAP = {1: 1, 2: 2, 3: 3}
    candidates = []
    for w in words:
        if w["id"] in processed:
            continue
        if args.tier and w.get("frequency", 3) != args.tier:
            continue
        if needs_enrichment(w):
            candidates.append(w)

    # Sort by tier (1 first)
    candidates.sort(key=lambda w: w.get("frequency", 3))

    if args.limit:
        candidates = candidates[:args.limit]

    print(f"Candidates for enrichment: {len(candidates):,}")
    if not candidates:
        print("Nothing to do.")
        return

    # Tier breakdown
    tier_counts = {}
    for w in candidates:
        t = w.get("frequency", 3)
        tier_counts[t] = tier_counts.get(t, 0) + 1
    for t in sorted(tier_counts):
        print(f"  Tier {t}: {tier_counts[t]:,}")

    print(f"\nStarting enrichment...")
    print("-" * 60)

    # Setup
    client = AsyncOpenAI(base_url=f"{API_URL}/v1", api_key=API_KEY)
    semaphore = asyncio.Semaphore(args.concurrency)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    # Process in batches of concurrency*2 for progress tracking
    batch_size = args.concurrency * 3
    total = len(candidates)
    success = 0
    failed = 0
    start_time = time.time()

    with open(OUTPUT_PATH, "a", encoding="utf-8") as out_f:
        for batch_start in range(0, total, batch_size):
            batch = candidates[batch_start:batch_start + batch_size]
            tasks = [enrich_one(client, w, semaphore) for w in batch]
            results = await asyncio.gather(*tasks)

            for spelling, result in results:
                if result:
                    out_f.write(json.dumps(result, ensure_ascii=False) + "\n")
                    success += 1
                else:
                    failed += 1
                processed.add(spelling)

            # Progress
            done = batch_start + len(batch)
            elapsed = time.time() - start_time
            rate = done / elapsed if elapsed > 0 else 0
            eta = (total - done) / rate if rate > 0 else 0
            print(f"  [{done:,}/{total:,}] ✅{success} ❌{failed} | {rate:.1f} words/s | ETA: {eta:.0f}s")

            # Save checkpoint every batch
            save_checkpoint(processed)
            out_f.flush()

    # Final stats
    elapsed = time.time() - start_time
    print("-" * 60)
    print(f"Done in {elapsed:.0f}s ({elapsed/60:.1f} min)")
    print(f"  Success: {success:,}")
    print(f"  Failed:  {failed:,}")
    print(f"  Output:  {OUTPUT_PATH}")
    print(f"  Checkpoint: {CHECKPOINT_PATH}")
    print(f"\nNext step: run scripts/merge_ai_enrichment.py to merge into words.json")


if __name__ == "__main__":
    asyncio.run(main())
