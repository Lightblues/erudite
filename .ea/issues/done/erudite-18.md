---
id: erudite-18
title: "Data pipeline: ECDICT enrichment + AI batch generation"
status: done
priority: high
estimate: L
---

## Objective

Enrich the bundled 13K word database with additional metadata (phonetics, frequency, exam tags) from ECDICT, and generate AI content (mnemonics, examples, synonyms/antonyms) via batch API calls for improved learning experience.

## Context

- `scripts/enrich_ecdict.py` — **Created** — ECDICT enrichment pipeline (fills phonetics, BNC/COCA freq, exam tags, english defs)
- `scripts/enrich_ai.py` — **Created** — AI batch enrichment (10 concurrent, checkpoint/resume, tier-priority)
- `scripts/merge_ai_enrichment.py` — **Created** — Merge JSONL AI results back into words.json
- `scripts/eval_sources.py` — **Created** — Data source comparison tool (25 words × 4 sources)
- `scripts/test_enrich_ecdict.py` — **Created** — ECDICT enrichment test (10 words)
- `scripts/test_enrich_ai.py` — **Created** — AI enrichment test (5 words)
- `Erudite/Erudite/Resources/Data/words.json` — **Updated** — One-word-per-line format, enriched with ECDICT + AI data
- `.env` — **Created** (git-ignored) — API config (ENRICH_API_URL, ENRICH_API_KEY, ENRICH_MODEL)
- `.gitignore` — **Modified** — Added data/ai_enriched_words.jsonl, checkpoint, .env
- `.ea/spec/data.md` — **Rewritten** — New architecture (Bundled + Dynamic), pipeline docs
- `pyproject.toml` — **Modified** — Added openai, python-dotenv dependencies

## Results

### ECDICT Enrichment (full, complete)
- 13,078/13,112 words matched (99%)
- +2,584 phonetics filled
- +7,361 english definitions filled
- +12,272 BNC/COCA frequency ranks added
- +10,716 exam tags added (gre/toefl/ielts/cet4/cet6)

### AI Batch Enrichment (first batch merged)
- 550 words enriched (gemini-3.1-flash-lite, 10 concurrent)
- +390 mnemonics (word root breakdowns in Chinese)
- +119 examples
- +269 synonyms supplemented
- +529 antonyms added
- +97 concise Chinese definitions

### words.json Format
- One-word-per-line: valid JSON, git-friendly diffs
- Alphabetically sorted for stable diffs
- 6.2 MB, 13,112 words

## Pipeline Commands

```bash
# Full pipeline (in order)
uv run scripts/build_worddb.py
uv run scripts/build_multibook.py
uv run scripts/enrich_ecdict.py
uv run scripts/enrich_ai.py          # 10 concurrent, ~95 min for 13K
uv run scripts/merge_ai_enrichment.py

# AI enrichment options
uv run scripts/enrich_ai.py --tier 1          # Core words only
uv run scripts/enrich_ai.py --limit 100       # Test batch
uv run scripts/enrich_ai.py --reset           # Clear checkpoint
```

## Acceptance

- [x] ECDICT enrichment fills phonetics/frequency/tags for 99% of words
- [x] AI enrichment generates quality mnemonics + examples (verified on 10 samples)
- [x] Merge script correctly integrates AI results without overwriting rich existing data
- [x] words.json format is git-friendly (one word per line, sorted)
- [x] Pipeline is resumable (checkpoint file)
- [x] API keys in .env (not committed)
- [x] `xcodebuild build` succeeds with enriched data
