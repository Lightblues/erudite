# Data Sources

Raw vocabulary data for building Erudite's word database.

## Directory Structure

```
data/
├── README.md           ← You are here
└── raw/                ← Source files (gitignored)
    ├── GRE_3.json      ← Primary: 新东方 GRE 6515 词 (kajweb/dict)
    ├── GRE_2.json      ← Supplement: 有道 GRE 7199 词 (kajweb/dict)
    ├── L-GRE-再要你命3000.csv   ← Frequency signal (LER0ever/GRE-CN)
    ├── L-GRE-MagooshFlashcard.csv  ← Frequency signal + EN examples
    └── L-GRE-佛脚词表.csv         ← Reference (not used in build)
```

## Source Details

| File | Source | Words | Fields | Role |
|------|--------|-------|--------|------|
| **GRE_3.json** | [kajweb/dict](https://github.com/kajweb/dict) (新东方) | 6515 | 音标、中英释义、例句、同义词、助记、同根词 | Primary data |
| **GRE_2.json** | [kajweb/dict](https://github.com/kajweb/dict) (有道) | 7199 | 音标、中英释义、例句、同义词 | Supplement |
| **L-GRE-再要你命3000.csv** | [LER0ever/GRE-CN](https://github.com/LER0ever/GRE-CN) | 3033 | 词、中文释义、英文释义 | Frequency tier signal |
| **L-GRE-MagooshFlashcard.csv** | [LER0ever/GRE-CN](https://github.com/LER0ever/GRE-CN) | 1008 | 词、英文释义、例句 | Frequency tier signal |
| **L-GRE-佛脚词表.csv** | [LER0ever/GRE-CN](https://github.com/LER0ever/GRE-CN) | ~2500 | 词、词性、中文释义 | Reference only |

## How to Obtain

```bash
# 1. kajweb/dict — download GRE_2 and GRE_3 ZIP from releases
#    https://github.com/kajweb/dict
#    Extract to data/raw/GRE_2.json and data/raw/GRE_3.json

# 2. LER0ever/GRE-CN — clone and copy relevant CSVs
git clone https://github.com/LER0ever/GRE-CN.git /tmp/GRE-CN
cp "/tmp/GRE-CN/L-GRE-词汇/L-GRE-再要你命3000/L-GRE-再要你命3000顺序版/L-GRE-再要你命3000.csv" data/raw/
cp "/tmp/GRE-CN/L-GRE-词汇/L-GRE-Magoosh/L-GRE-MagooshFlashcard.csv" data/raw/
cp "/tmp/GRE-CN/L-GRE-词汇/L-GRE-佛脚词汇/L-GRE-佛脚词汇/L-GRE-佛脚词表.csv" data/raw/
```

## Build Pipeline

```bash
# From project root:
uv run scripts/build_worddb.py

# Output: Erudite/Erudite/Resources/Data/words.json (5.6MB, 6515 words)
```

## Frequency Tiering Strategy

Cross-reference multiple sources to determine word priority:

```
Core (tier 1, ~524 words):     in BOTH Magoosh AND 再要你命3000
Common (tier 2, ~1750 words):  in 再要你命3000 (but not Magoosh)
Advanced (tier 3, ~4241 words): remaining GRE_3 words
```

## Field Coverage (output words.json)

| Field | Coverage | Source |
|-------|----------|--------|
| phonetic | 100% | GRE_3 |
| definitions (CN+EN) | 100% | GRE_3 |
| synonymGroups | 91% | GRE_3 |
| examples | 90% | GRE_3 + Magoosh |
| mnemonics | 65% | GRE_3 (remMethod) |
| roots | 0% | TODO: AI batch enrichment |
| antonyms | 0% | TODO: AI batch enrichment |
| sentiment | 0% (all neutral) | TODO: AI classification |
