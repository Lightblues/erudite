
## optim Library
下面, 我们来优化 Library 页面:
0. 整个词库的问题: 我们之前导入了一份词表, 但里面很多内容是欠缺的; 后面用 ai-enrich 的范式补全了 Erudite/Erudite/Resources/Data/words.json 词库; 
  1. 如何分析两者之前的差异, 更新 DB?
1. 目前的 Tier 是如何划分的? 是不是之前 GRE 某个单词本的概念? 权威吗? 是否还有参考价值?
2. 默认的 Book 应该是我们选中正在学的那本, 而不是默认 "All Books"
3. state 的 new/learning/review/mature 是如何划分的? FSRS 中的概念吗? 
  1. 我选择 state 是有效的, 但是下面列表中状态都是 "New"?
4. 介绍一下 Sort 中的 4 中排序算法?
```sh
# 同步策略 — 三选一
┌──────────────────┬──────────────────────────────────────────┬────────────────────────────────┐
│       方案       │                   优点                   │              缺点              │
├──────────────────┼──────────────────────────────────────────┼────────────────────────────────┤
│ A. 字段级 merge  │ 安全:只填 DB                             │ 实现复杂,要 JSON path 级合并   │
│ (推荐)           │ 里缺失的字段;不会覆盖你手动改过的内容    │                                │
├──────────────────┼──────────────────────────────────────────┼────────────────────────────────┤
│ B. 全量 INSERT   │ 简单,一行 SQL                            │ 如果将来加用户编辑字段会丢失   │
│ OR REPLACE       │                                          │                                │
├──────────────────┼──────────────────────────────────────────┼────────────────────────────────┤
│ C.               │ 干净                                     │ 用户的 reviewCard              │
│ 版本号驱动重灌   │                                          │ 不能丢,要分两张表处理          │
└──────────────────┴──────────────────────────────────────────┴────────────────────────────────┘

# Sort 算法说明
┌───────────┬───────────────┬───────────────────────────────────────────────────────────────────┐
│   选项    │ SQL ORDER BY  │                               用途                                │
├───────────┼───────────────┼───────────────────────────────────────────────────────────────────┤
│           │ w.frequency,  │ Tier 1(core)→ 2(common)→ 3(advanced),同 tier 内字母序。问题:80%   │
│ Frequency │ w.spelling    │ 词都在 advanced,实际呈现的是 524 + 1779 个词分组在前,然后剩下 10K │
│  (默认)   │ COLLATE       │  词全部按字母排 — 头部分组有意义,尾部基本就是字母序               │
│           │ NOCASE        │                                                                   │
├───────────┼───────────────┼───────────────────────────────────────────────────────────────────┤
│           │ w.spelling    │                                                                   │
│ A → Z     │ COLLATE       │ 纯字母序。最稳定、最可预测;查找特定词时最有用                     │
│           │ NOCASE        │                                                                   │
├───────────┼───────────────┼───────────────────────────────────────────────────────────────────┤
│           │ (rc.dueDate   │                                                                   │
│ Due Date  │ IS NULL),     │ 「最该复习的在前」。NULL(没卡 /                                   │
│           │ rc.dueDate    │ 新卡)排到最后;然后过期最久的在最上面。用于「我现在该刷哪些」      │
│           │ ASC, ...      │                                                                   │
├───────────┼───────────────┼───────────────────────────────────────────────────────────────────┤
│           │ (rc.lapses IS │                                                                   │
│ Most      │  NULL),       │ 「我经常忘记的在前」。lapses 是历史上从 review 状态跌落到         │
│ Lapses    │ rc.lapses     │ relearning 的次数。用于复盘弱点                                   │
│           │ DESC, ...     │                                                                   │
└───────────┴───────────────┴───────────────────────────────────────────────────────────────────┘
# 我的建议改进
1. 在选中 Book 时,加一个隐式的 Book 内顺序排序 — 也就是 wordListEntry.sortOrder,这是 GRE 3000 这种「按书的顺序」教材原本应有的默认序
2. Due Date / Lapses 排序时,如果一开始 80% 卡片都是 nil(state=0),NULL-last 把所有有意义的内容堆在最前面 ~110 行,后面全是 nil — 这其实蛮合理的,但用户可能希望「Sort: Due Date 时自动 hide cards 没有 review 数据的词」。可以在选这两个排序时,自动 disable state == .all → 只显示 learning/review/relearning,把新卡过滤掉
3. 加 frequency × spelling 的组合排序索引:
CREATE INDEX idx_word_freq_spelling ON word (frequency, spelling COLLATE NOCASE);
3. 你现在每次 Library 都做全表 scan + sort,加个索引 sort 可以走索引免排序
```
两个方向都可以帮我做一下
- 另外, 我还是感觉 Tier 的划分没什么价值, 可以先删掉? 后续有必要的话, 用词频统计之类的更为合理?
```sh
# docs
- features.md, data.md, lessons.md updated
- .ea/issues/done/erudite-25.md created
```


## libray Overview
继续优化 Library UI:
- 整体 UI:
  - 目前单词 list 和右侧的 Word detail 划分基本是均分, 可否布局可调整呢? (调整宽度, 另外参考 mail 布局的话左侧更窄)
- 单词列表:
  - 目前最左侧的小圆圈 (中间有个M) 是什么意思?
  - 每次进入 Library 都是从头开始 a**, 是不是可以加上分页逻辑?
  - 目前 DB 里面单个 Word 有哪些属性 (列)? 能够设置某些列在单词列表中显示呢? (是否是伪命题? 我在 overall 查看的时候需要看哪些字段?)
- 关联的问题是: 如何检查 DB 中 words 数据完整性 (检查 DB)? 之前你是如何merge v3 数据的?
- 另外关联的是 flashcard 里面的学习策略:
  - 参考专门背单词本的设置, 会使用一个 unit (e.g. 10~15) 来划分;
  - 我觉得 Erudite 应该也类似 -- 控制每次 review/learn 的单词数量; 每个 unit 完整之后给一个 summary; 然后继续 -- 避免一次 review 计划 100+单词 很绝望
  - 你觉得应该如何优化背单词的机制呢?
```sh
┌─────────────────────┬────────────────────────────────────────────────────────────────────────┐
│       选择点        │                                  推荐                                  │
├─────────────────────┼────────────────────────────────────────────────────────────────────────┤
│ Unit size           │ 可配,默认 12;在 Settings 里可调 8/12/15/20                             │
├─────────────────────┼────────────────────────────────────────────────────────────────────────┤
│ Unit 怎么 mix       │ Reviews 先 + New 后(优先复盘记忆衰减,再学新);per-unit 内可配比例(80%   │
│                     │ review / 20% new)                                                      │
├─────────────────────┼────────────────────────────────────────────────────────────────────────┤
│ Unit 完成后默认动作 │ Continue(回车),Esc 退出                                                │
├─────────────────────┼────────────────────────────────────────────────────────────────────────┤
│ Summary 显示什么    │ 学过的词 mini-grid(各自颜色 = rating),accuracy,本 unit 用时,FSRS       │
│                     │ 提示("3 个词稳定性提升")                                               │
├─────────────────────┼────────────────────────────────────────────────────────────────────────┤
│ New words 限制      │ 沿用现在的 dailyNewLimit;Unit 之间共享配额,不是每个 unit 重置          │
├─────────────────────┼────────────────────────────────────────────────────────────────────────┤
│ Session interrupt   │ 当前 unit 进度保留(已 review 的词 FSRS 已经写了),下次进来从下一个 unit │
│ 半路                │  开始                                                                  │
└─────────────────────┴────────────────────────────────────────────────────────────────────────┘
```
整体回顾一下对于分 unit 的策略:
1. 目前安排服务的逻辑是什么? FSRS 算法机制如何?
2. Today 页面:
  1. start learning / review due 的差异是什么? 应该用如何策略区分两种模式?
  2. 下面 reviews / new 单词列表是如何筛选的?
3. Plan 页面:
  1. New words queue; overdue/today/tomorrow/this week 词表的逻辑是什么? 和 Today 页面的词表有何差异?
4. Flashcard 页面:
  1. 一点进去就开始的 Unit 是什么? 如何排序的? Word list 是如何构建的?
  2. 我感觉还是没有使用 "GRE 3000 词" 那种点击一个 Unit, 学完 10~15 单词之后快速反馈的感觉, 如何优化体验? (e.g. 一开始 "进入 Unit" 的时候就预览要学的这个单元?)
5. Typing 页面:
  1. 选词逻辑应该和 Flashcard 页面是同步的? 目前是不是独立的两套逻辑
  2. 单词状态: 目前对于学习进度, 后台数据结构是怎样的? 如何将 Typing 练习也纳入到FSRS 体系中?
```sh
# 调度逻辑 + FSRS 现状
FSRS 引擎(Engine/FSRS/FSRSEngine.swift)

这是个 stub 实现(注释里写了"Full algorithm implementation in a future issue")。目前的"调度"是固定写死的乘子:

┌─────────────────┬────────────────┬──────────────────┐
│    状态转移     │ Stability 变化 │       间隔       │
├─────────────────┼────────────────┼──────────────────┤
│ New → Easy      │ 4.0 days       │ 4 天             │
├─────────────────┼────────────────┼──────────────────┤
│ Learning + Good │ 3.0            │ 1 天             │
├─────────────────┼────────────────┼──────────────────┤
│ Review + Good   │ × 2.5          │ 已有间隔 × 2.5   │
├─────────────────┼────────────────┼──────────────────┤
│ Review + Again  │ × 0.5          │ 10 分钟,lapses+1 │
└─────────────────┴────────────────┴──────────────────┘

真实 FSRS-5 算法的核心:
- 17 个学习参数(记忆稳定性 stability + 难度 difficulty 的更新公式系数)
- 每个 rating 后用公式更新 stability/difficulty,依据真实的"遗忘曲线":R(t) = (1 + t/(9·S))^-1
- 调度逻辑:next due = stability × ln(retention_target) / ln(0.9),retention_target 默认 0.9

当前问题:
- 间隔扩张固定 ×2.5,不基于真实记忆曲线
- 个体 difficulty 没有跟踪(每个词当前都是 5.0,从不变)
- 没有 desired retention 概念
```
```sh
# 调度数据流
ReviewCard (FSRS state per word)
  ├─ wordId
  ├─ stability, difficulty
  ├─ state: new(0) | learning(1) | review(2) | relearning(3)
  ├─ dueDate
  ├─ reps, lapses
  └─ lastReview

reviewLog (history of every rating event)
  └─ cardId, rating, state, timestamp, intervals, duration
```
```sh
# 选词 SQL(关键!)
这是问题的核心 — 不同页面用不同函数:

┌─────────────┬─────────────────────────────────────┬────────────────────────────────────────────────┐
│   调用方    │                函数                 │                    选词逻辑                    │
├─────────────┼─────────────────────────────────────┼────────────────────────────────────────────────┤
│ Today       │ fetchDueSummaries(limit: 50)        │ state != 0 AND dueDate <= now ORDER BY dueDate │
│ preview     │                                     │                                                │
├─────────────┼─────────────────────────────────────┼────────────────────────────────────────────────┤
│ Today       │ fetchNewWordSummaries(limit: 50)    │ state = 0 ORDER BY wle.sortOrder               │
│ preview     │                                     │                                                │
├─────────────┼─────────────────────────────────────┼────────────────────────────────────────────────┤
│ Plan        │ fetchDueCountsByDay(7)              │ 按天 group,未来 7 天                           │
│ workload    │                                     │                                                │
├─────────────┼─────────────────────────────────────┼────────────────────────────────────────────────┤
│ Plan        │ fetchDueBacklog(perBucket: 100)     │ 5 个                                           │
│ backlog     │                                     │ bucket(overdue/today/tomorrow/thisWeek/later)  │
├─────────────┼─────────────────────────────────────┼────────────────────────────────────────────────┤
│ Plan new    │ fetchNewWordSummaries(limit: 50)    │ 同 Today                                       │
│ queue       │                                     │                                                │
├─────────────┼─────────────────────────────────────┼────────────────────────────────────────────────┤
│ Flashcard   │ fetchDueCards(inBook:) +            │ 全部 due + 10 new                              │
│ 实际学      │ fetchNewCards(limit: 10)            │                                                │
├─────────────┼─────────────────────────────────────┼────────────────────────────────────────────────┤
│ Library     │ fetchWordSummaries(sort: .dueDate)  │ 全部按 due 排,NULL 最后                        │
│ Sort=Due    │                                     │                                                │
└─────────────┴─────────────────────────────────────┴────────────────────────────────────────────────┘

关键观察:
- Today/Plan 的"列表"(预览)用 *Summaries (SELECT 投影)
- Flashcard 实际学的时候 用 fetch*Cards (返回 ReviewCard 对象)
- 两套查询函数,不同 SQL,虽然语义上是同一种东西 — 这本身就是技术债
```
```sh
# 两种范式不冲突,可以共存:
Today 页:
  ┌─ FSRS-driven actions (复习引擎主导)
  │  • Review Due (33)
  │  • Daily Mix (Reviews + 12 new)
  └─ Book-driven actions (用户主导)
     • Continue: Unit 5 of GRE 3000  [13 / 15 done]
     • Browse all units →
```
```sh
# 数据结构再回顾

Word 表           ← 词典数据(spelling、释义、phonetic、mnemonic、tags)
reviewCard 表     ← FSRS 状态(state、stability、due、reps、lapses)
reviewLog 表      ← Flashcard 每次 rating 的历史
typingLog 表      ← Typing 每个词每次完成的历史
user_content 表   ← 用户笔记 / 自定义 mnemonic
wordListEntry 表  ← Word 在 Book 中的顺序

→ Flashcard 写 reviewCard + reviewLog,Typing 只写 typingLog。
```
```sh
# 建议的实施顺序
┌───────────┬───────────────────────────────────────────┬────────────────┐
│  优先级   │                   工作                    │      预估      │
├───────────┼───────────────────────────────────────────┼────────────────┤
│ P0 (基石) │ 把 Unit 变成数据结构 + 预览页             │ 3h             │
├───────────┼───────────────────────────────────────────┼────────────────┤
│ P0        │ Typing 写 FSRS rating(derivedRating 那种) │ 1.5h           │
├───────────┼───────────────────────────────────────────┼────────────────┤
│ P1        │ Today 改成"Unit 选择器"形态               │ 2h             │
├───────────┼───────────────────────────────────────────┼────────────────┤
│ P1        │ 选词管道统一为 StudyQueueBuilder          │ 2h             │
├───────────┼───────────────────────────────────────────┼────────────────┤
│ P2        │ 真正 FSRS-5 算法替换 stub                 │ 4h(单独 issue) │
└───────────┴───────────────────────────────────────────┴────────────────┘
User answered Claude's questions:
· Unit 主要什么驱动? → 两者并存 (Today 页同时列出)
· Typing 怎么入 FSRS? → Typing 完成 → 应用 derived rating (推荐)
· 这轮做多少? → 感觉可以把 P0,P1 一起做了, 但不要进入 Plan 模式, 一边和我讨论, 明确后直接开始实现

User answered Claude's questions:
· 每日新词配额怎么看? → New 词独立 unit (不自动拼入 Reviews)
· Book Chapter 多大? → 我觉得系统默认可以设置为 12, 但后面应该是可配置的! (作为参数预留出来)
· Typing→FSRS 门控多严? → 我觉得 Flashcard & Typing 的选 Unit 逻辑应该是一致的? 两者只是不同的学习方法! 因此上面讨论的组 Unit 的逻辑是可复用的, 交互也和进入 Flashcard 的策略一样?

# 关键洞察:Unit 是公共的,Flashcard 和 Typing 是消费 unit 的不同方式。
我重新规划方案:

StudyUnit (共享数据结构)
   ↑                ↑
   │                │
Flashcard 模式    Typing 模式
   │                │
   └─→ rate()      └─→ on word complete: derived rating
       FSRS 写入        (如果在 unit 模式 + due 卡片)

进入路径:
- Today 列 unit → 点 unit → Unit Preview(扫读) → 选 [Flashcard] / [Typing] → 开始
- Typing tab 直接打开:保留现在的 chapter 浏览(独立模式,不写 FSRS)

Unit Size:全局可配,默认 12,Settings 里能调,Flashcard/Book Chapter 共用。
```
```sh
# 实现: What changed (commits e4fde91 → 08b481e)
┌────────────┬────────────────────────┬──────────────────────────────────────────────────────────────┐
│   Layer    │         Before         │                            After                             │
├────────────┼────────────────────────┼──────────────────────────────────────────────────────────────┤
│ Engine     │ fetchDueCards +        │ StudyUnit + StudyQueueBuilder (single source)                │
│            │ fetchNewCards per-call │                                                              │
├────────────┼────────────────────────┼──────────────────────────────────────────────────────────────┤
│ Today      │ 3 hard-coded buttons   │ List of StudyUnit cards + summary "4 units · ~22 min"        │
├────────────┼────────────────────────┼──────────────────────────────────────────────────────────────┤
│ Pre-study  │ None                   │ UnitPreviewView sheet — scan-read 12 words, pick Flashcard / │
│            │                        │  Typing                                                      │
├────────────┼────────────────────────┼──────────────────────────────────────────────────────────────┤
│ Flashcard  │ One entry path,        │ Two paths: unit-driven (the unit IS the session) vs legacy   │
│            │ dynamic 12-slice       │ (still works)                                                │
├────────────┼────────────────────────┼──────────────────────────────────────────────────────────────┤
│ Typing →   │ None — Typing was an   │ applyDerivedFSRSRatingIfApplicable: 0/1-2/3+ mistakes →      │
│ FSRS       │ island                 │ Good/Hard/Again, gated to mature + due cards only            │
├────────────┼────────────────────────┼──────────────────────────────────────────────────────────────┤
│ Settings   │ study_unitSize read    │ AppSettings.unitSize (12, range 5-30, persisted, single      │
│            │ directly in StudyVM    │ source for Flashcard chunk + Book Chapter + Today's slicer)  │
└────────────┴────────────────────────┴──────────────────────────────────────────────────────────────┘
```

我觉得体验上可以优化的地方:
1. Today 页面:
  1. review/new 模式 vs 书籍 list 选择: 应该是两种模式, 没必要混在一起, 后者也不叫 "today's plan"
    我感觉要么在 Today 里面左右划分/新增tab 选择来区分; 要么后续放进 Plan 页面中?
  2. 我希望有一个 "今日学习内容" 的回顾, 有个 list 看到我所有背诵的列表 & 标记情况 (错多的置顶).
2. Flashcard & Typing 页面: 目前单独点开这两个 tab 的逻辑是什么? 
  1. 是不是还是复用了之前的逻辑? 我感觉应该也接入 Today 的选 Unit 逻辑?
  2. 还有最后的回顾页面, 两者是不是也不统一?
总体来说, 我希望简化一下, 统一这些页面的交互逻辑, 这样用户更好理解, 代码实现层也更好抽象
```sh
# Today 页面重新分层

┌── Today ─────────────────────────────────────┐
│ Greeting / book picker / stats strip          │
│                                                │
│ ─── Today's homework ─────────────             │   ← 只 FSRS-driven
│ ↻ Reviews · 1   12 cards · ~5m  →             │
│ ↻ Reviews · 2   12 cards · ~5m  →             │
│ +  New words    12 cards · ~6m  →             │
│                                                │
│ ─── Today's recap (NEW) ────────              │   ← 新增
│ • belligerent  Again × 2  3 mistakes          │
│ • supplant     Hard       1 mistake           │
│ • myriad       Good                           │
│ ⋯ 7 words touched today                       │
│                                                │
│ ─── Browse (NEW location for book chapters) ─ │   ← 看下面 ❓
│ 📕 GRE 3000 — Continue chapter 3              │
│ ─── Two-column preview (existing, optional) ─ │
└────────────────────────────────────────────────┘

# 抽象层 — 代码组织
Engine/
  StudyUnit.swift              (existing)
  StudyQueueBuilder.swift      (existing)
  SessionResult.swift          (NEW: unified shape)
  TodayRecap.swift             (NEW: today's-learning query model)
Services/
  DatabaseService+Recap.swift  (NEW: fetchTodayRecap query)
Views/Study/
  SessionSummaryView.swift     (NEW: shared by Flashcard/Typing complete)
  ...
Views/Components/
  UnitPickerView.swift         (NEW: shared by Today / empty Flashcard / empty Typing)
```
```sh
# 痛点诊断 → 修复
┌─────────────────────────────────┬────────────────────────────────────────────────────┬───────────────────────────────────────────┐
│              痛点               │                        之前                        │                   之后                    │
├─────────────────────────────────┼────────────────────────────────────────────────────┼───────────────────────────────────────────┤
│ Today 把 FSRS homework 和 book  │                                                    │ 拆开:Today = "Today's homework"(只 FSRS)  │
│ chapter 混在 "Today's plan"     │ 一个列表两种语义                                   │ + 新增 "Today's recap";chapter 移到       │
│                                 │                                                    │ Library                                   │
├─────────────────────────────────┼────────────────────────────────────────────────────┼───────────────────────────────────────────┤
│ 直接点 Flashcard / Typing tab → │ start(database:mode:.mixed) / 持久化 chapter       │ 空态显示 UnitPickerView(跟 Today 一样的   │
│  跑 legacy 路径,跟 Today 不一致 │                                                    │ unit 列表)                                │
├─────────────────────────────────┼────────────────────────────────────────────────────┼───────────────────────────────────────────┤
│ 3 个完成页 3 套布局             │ .complete(party popper)/ .unitComplete(紧凑卡)/    │ 统一为 SessionSummaryView + 共享          │
│                                 │ chapterCompleteView(WPM/accuracy)                  │ SessionResult 结构                        │
├─────────────────────────────────┼────────────────────────────────────────────────────┼───────────────────────────────────────────┤
│ Book chapter 没地方好好浏览     │ 只能从 Today 看到下一个 unit                       │ Library 加 Words / Chapters segmented,选  │
│                                 │                                                    │ chapter → UnitPreview                     │
└─────────────────────────────────┴────────────────────────────────────────────────────┴───────────────────────────────────────────┘
```

## Overview workflow
总结一下之前的实现:
1. 统一了 Unit 语义 (UnitPreview) -- today/flashcard/typing 页面采用相同的入口, 用户体验一致
2. 统一的学习 summary 页面 (& 数据, 方便后续汇总)
3. 分析对于书籍结构 Unit 的学习模块 -- 放到 Library 中.
我觉得非常好! 后续可优化的地方:
- Today's reacp: 通过 status+word 的形式展示可行; 
  - 但是 list 太长了, 是否需要考虑分页 or 分 tab 筛选?
    - 感觉没必要这么复杂? 后续 Typing/新的复习模式所引入的词汇也可能放进来, 整体模式需要简化
  - 不过一个切实的需求是, 针对这些 "recap" 的词汇, 我希望能够再次复习 -- 也即, 在 FSRS 的自动化生成背诵方案之外, 自由地对于今天学习的词汇做复习.
    - 评估一下, 这个需求合理吗? 整体 review 一下目前我的背单词的 ideas, 是不是有点太散了? 应该有一个 overall 的 workflow?
- Today 页最后的 reviews/new list: 我感觉和 Plan 页重叠了? 移过去
- Plan 页: 
  - 上面的统计指标: 保留.
  - "new words queue" & today/tomorrow/this week/later list: 我感觉和上面Today 页重叠了? 
    - 重新组织一下, 目前两部分上下划分滚动起来很麻烦, 可能分 tab 更为合理?
先跟我讨论方案, 后续再实现
```sh
# 重新划定语义边界
整体 workflow 应该是这样:

                 ┌─ Today  = "今日:做 + 已做"
                 │         · homework (FSRS 自动)
                 │         · recap    (今日已学)  ← 增加 "Re-review" 入口
   学习 surface ─┤
                 └─ Plan   = "节奏:看全局"
                           · Roadmap + 7d chart  (overview)
                           · [New | Due]         (worklist, 切换)

   学习 entry ─── Library Chapter (按书自由选)
                  ↓
   统一 pipeline ─ UnitPreview → Flashcard/Typing → SessionSummary

两种学习模式,共用一套 unit pipeline:
- 自动模式 (FSRS 说): Today's homework
- 自主模式 (你选): Library chapter · Today's recap re-review (NEW)

—— 都是 StudyUnit,都走 UnitPreview,都用 SessionSummary。新需求不"散",反而是把现有抽象用得更深。
```
Plan 采用方案 1 -- 概要+词汇信息挺好的. 相较于 "Segmented [New | Due]", 我感觉 "today/tomorrow/this week/later + new (next queue)" 的划分是不是更有全局概览性?
```sh
· Recap 的 re-review,Flashcard 评分是否回写 FSRS schedule? → 不回写 (推荐)
· Recap re-review 的范围:全部今日词汇,还是只"待改进"子集? → 只"待改进"子集 (推荐)
· Plan 重组方式偏好? → Plan 采用方案 1 -- 概要+词汇信息挺好的. 相较于 "Segmented [New | Due]", 我感觉 "today/tomorrow/this week/later + new (next queue)" 的划分是不是更有全局概览性?
```
- "Plan 重组": 不对, 不是 "时间线视图", 而是用 tab 来区分 -- 避免过长滚动
- 再给我解释一下 "Re-review" 的算法逻辑? 或者让用户自行选择呢?
```sh
┌───────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────┐
│               痛点                │                                          落地方案                                          │
├───────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
│ Recap 太长 + 没法 act on          │ 每行 checkbox + 默认勾 needsWork + 底部 [Re-review · K]                                    │
├───────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
│ 同一份数据 Today 双栏 + Plan 也有 │ Today 双栏删掉,数据全归 Plan                                                               │
├───────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
│ Plan 上下两段一起滚               │ 顶部 Roadmap+Chart 固定,底部 5 个 tab 切换                                                 │
├───────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤
│ Recap re-review 怕扰乱 FSRS       │ Kind.skipsFSRSWriteback 单旗,两个 ViewModel 入口判断 → 只展示 SessionSummary,不动 schedule │
└───────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────┘
```

两点反馈:
- Today 页面最好加上 "今天做了什么的统计", 包括学习几个 unit (几个 Flashcard/Typing); words (复习/新词) 
  - 同样在数据层做好 API, UI 层仅作显示
- "Plan 上下两段一起滚" 是合理的 -- 因为上面的 roadmap & new 7-day workload 都是一次性 "预览" 的, 用户可能关系的是后续学习 Word list, 应该允许通过下滑来占据整个评估, 不然信息量太小了!
```sh
# Lessons 总结的两个原则
1. Fixed regions only earn their pin if always-actionable ─ "always relevant for context" ≠ "always actionable"。preview-y 信息让它跟着滚。
2. Data API owns semantics ─ view 拿到 TodayActivityStats 直接渲染,不需要复合 query 或应用业务规则。30 分钟阈值、state == 0 检测,所有"什么算 session / 什么算 new word" 的判断都在 API 里。
```
