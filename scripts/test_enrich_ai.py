#!/usr/bin/env python3
"""
Test script: Enrich words using AI (OpenAI-compatible API).

Takes 5 sample words and generates structured enrichment data:
- Chinese definition (concise, for memorization)
- English definition (simple)
- Example sentence (with Chinese translation)
- Mnemonic (word root breakdown for Chinese learners)
- Synonyms & Antonyms

Uses streaming OpenAI chat.completions format.

Usage: uv run scripts/test_enrich_ai.py
"""

import json
import os
from openai import OpenAI
from dotenv import load_dotenv

# API config
load_dotenv()
URL = os.environ.get("ENRICH_API_URL", "")
KEY = os.environ.get("ENRICH_API_KEY", "")
MODEL = os.environ.get("ENRICH_MODEL", "")

WORDS_PATH = "Erudite/Erudite/Resources/Data/words.json"

SYSTEM_PROMPT = """You are a vocabulary enrichment assistant for a GRE/TOEFL vocabulary learning app targeting Chinese-speaking learners.

For each word, generate structured data in JSON format. Focus on:
1. Concise Chinese definitions suitable for quick memorization (not dictionary-style verbose)
2. Simple English definitions (1 sentence, avoid jargon)
3. A natural example sentence showing typical usage
4. A mnemonic that connects word roots to meaning (in Chinese, for Chinese learners)
5. Key synonyms and antonyms

Output ONLY valid JSON, no markdown fences."""

USER_PROMPT_TEMPLATE = """Generate enrichment data for the word: "{word}"

Current data we have:
- Chinese: {chinese}
- English: {english}

Return JSON in this exact format:
{{
  "spelling": "{word}",
  "definitions": [
    {{"partOfSpeech": "adj/n/v/adv", "english": "<simple 1-sentence def>", "chinese": "<concise Chinese, max 10 chars>"}}
  ],
  "examples": [
    {{"sentence": "<natural English sentence>", "source": "AI"}}
  ],
  "mnemonics": ["<word root breakdown in Chinese, e.g. 'ab(离开) + err(走偏) → 异常的'>"],
  "synonyms": ["word1", "word2", "word3"],
  "antonyms": ["word1", "word2"]
}}"""


def find_sample_words(n=5):
    """Find words that need enrichment."""
    with open(WORDS_PATH, encoding="utf-8") as f:
        data = json.load(f)

    # Find words with sparse data
    samples = []
    for w in data["words"]:
        has_english = any(d.get("english") for d in w.get("definitions", []))
        has_mnemonic = bool(w.get("mnemonics"))
        if not has_english or not has_mnemonic:
            samples.append(w)
        if len(samples) >= n:
            break
    return samples


def enrich_word_ai(client: OpenAI, word: dict) -> dict | None:
    """Call AI to generate enrichment for a word."""
    spelling = word["spelling"]
    chinese = "; ".join(d.get("chinese", "") for d in word.get("definitions", []))
    english = "; ".join(d.get("english", "") for d in word.get("definitions", []) if d.get("english"))

    user_msg = USER_PROMPT_TEMPLATE.format(
        word=spelling,
        chinese=chinese[:100] or "(unknown)",
        english=english[:100] or "(unknown)",
    )

    try:
        # Streaming call
        stream = client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_msg},
            ],
            stream=True,
            temperature=0.3,
            max_tokens=500,
        )

        # Collect streamed response
        full_response = ""
        for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                full_response += chunk.choices[0].delta.content

        # Parse JSON (strip markdown fences if present)
        text = full_response.strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[1]  # remove first line
            if text.endswith("```"):
                text = text[:-3]
        text = text.strip()

        result = json.loads(text)
        return result

    except json.JSONDecodeError as e:
        print(f"    ⚠️  JSON parse error: {e}")
        print(f"    Raw: {full_response[:200]}")
        return None
    except Exception as e:
        print(f"    ⚠️  API error: {e}")
        return None


def main():
    print("=== AI Enrichment Test ===\n")
    print(f"API: {URL}")
    print(f"Model: {MODEL}\n")

    client = OpenAI(base_url=f"{URL}/v1", api_key=KEY)

    print("Finding words needing enrichment...")
    samples = find_sample_words(5)
    print(f"Selected: {[w['spelling'] for w in samples]}\n")

    print("=" * 60)
    for word in samples:
        sp = word["spelling"]
        print(f"\n🔄 Enriching: {sp}")
        print(f"   Current CN: {'; '.join(d.get('chinese','') for d in word.get('definitions',[])) [:60]}")

        result = enrich_word_ai(client, word)
        if result:
            print(f"   ✅ AI Result:")
            for d in result.get("definitions", []):
                print(f"      [{d.get('partOfSpeech','')}] {d.get('chinese','')} — {d.get('english','')[:50]}")
            for ex in result.get("examples", []):
                print(f"      📝 {ex.get('sentence','')[:60]}")
            for m in result.get("mnemonics", []):
                print(f"      💡 {m[:60]}")
            syns = result.get("synonyms", [])
            ants = result.get("antonyms", [])
            if syns:
                print(f"      🔗 Syn: {', '.join(syns[:5])}")
            if ants:
                print(f"      ⊕ Ant: {', '.join(ants[:3])}")
        else:
            print(f"   ❌ Failed")

    print("\n" + "=" * 60)
    print("\nDone.")


if __name__ == "__main__":
    main()
