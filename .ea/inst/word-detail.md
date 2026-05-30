
## feat: plan & Word Detail (in Library)
帮我 review 一下目前的进度:
- 整体上 flashcard & typing 练习的功能完成差不多了, 初步接入了 ai chat 能力
- 我感觉目前词库管理上比较欠缺. 主要问题:
  - 首页, 我不知道今天要学习/review的词表有哪些, 应该能够预览;
  - Library, 目前是显示所有词, 感觉会有一些性能问题? 可能分页比较合理?
- 补充能力 -- 对于 "词汇管理页面"
  - 点击一个单词, 显示数据库中的所有字段 -- 完整信息对于用户透明; 最好支持用户可修改 (管理后台数据)
  - 显示管理该词的学习进度 -- e.g. 出现过多少次, 目前学习状态如何
  - 显示该词所在的词书 (optional?)
- 回到 "学习/review" 的话题, 应该说, 当前系统对于 "学习计划" 的可视化很弱
  - 我希望能够看到整个学习计划 e.g. 后续的单词 list, 帮我想想这样的需求合理吗? 应该如何设计 UI?
先不要实现, 和我讨论一下交互设计
```sh
# 现状盘点
┌────────────────┬─────────────┬─────────────────────────────────┐
│      模块      │   完成度    │              评价               │
├────────────────┼─────────────┼─────────────────────────────────┤
│ Flashcard 学习 │ ✅ 完整     │ 状态机/快捷键/导航/统计都不错   │
├────────────────┼─────────────┼─────────────────────────────────┤
│ Typing 练习    │ ✅ 完整     │ qwerty-learner 风格, 章节系统   │
├────────────────┼─────────────┼─────────────────────────────────┤
│ AI Chat        │ ✅ 接入     │ 有 runtime/memory/tools/tracing │
├────────────────┼─────────────┼─────────────────────────────────┤
│ DB Schema      │ ✅ 充分     │ 表都建了, FSRS+Logs+Books+AI    │
├────────────────┼─────────────┼─────────────────────────────────┤
│ Today 页面     │ ⚠️ 仅有数字 │ 缺 "今天要学什么" 的可见性      │
├────────────────┼─────────────┼─────────────────────────────────┤
│ Library        │ ⚠️ 全量加载 │ 没用上已有的 fetchWordsPage     │
├────────────────┼─────────────┼─────────────────────────────────┤
│ WordDetail     │ ⚠️ 只读静态 │ 没接 ReviewCard / Logs / 编辑   │
├────────────────┼─────────────┼─────────────────────────────────┤
│ Plan 可视化    │ ❌ 几乎为零 │ 只能看 dueCount 数字            │
└────────────────┴─────────────┴─────────────────────────────────┘
```
```sh
# Today 页的 3 中视图
选项 A — Compact chips (推荐, 轻量)
== Today's Plan ==                      ~25 min · 22 words
  Reviews (12)  aberrant  coalesce  equivocate  garrulous  +8 more
  New (10)      obstreperous  perfidious  quintessence  +7 more
  [ Start Learning ]   [ Review Only ]   [ Skip preview ]

- 每个 chip 可点击 → popover 显示定义 (复用 WordPopoverView)
- "+8 more" 点击展开全部
- 优点: 1 屏内, 不挤压现有 quick stats
- 实现成本: 低 (复用现有组件)

选项 B — 两列滚动
┌─ Reviews (12) ──────────┐  ┌─ New (10) ──────────────┐
│ ● aberrant       2d过期  │  │ ◯ obstreperous          │
│ ● coalesce       1d过期  │  │ ◯ perfidious            │
│ ● equivocate     today  │  │ ◯ quintessence          │
│ ⋯                       │  │ ⋯                       │
└─────────────────────────┘  └─────────────────────────┘

- 信息更丰富 (能看到 due 多久了)
- 但占屏幕, Today 页变长
- 适合 "Plan tab" 而不是 Today

选项 C — AI 智能摘要 (野心, 后期)
今天的 22 个词分布在 3 个簇:
  • "speech" 系 (5 词): equivocate, garrulous, laconic ...
  • "negative emotions" 系 (4 词): aberrant, perfidious ...
  • 散落 (13 词)
```
```sh
# 学习计划
"整个学习计划" 这个表述要拆开:

┌───────────────────┬──────────────────────────────┬────────────────────────┐
│       维度        │          可视化方式          │          价值          │
├───────────────────┼──────────────────────────────┼────────────────────────┤
│ 下个 7 天的负担   │ 柱状图 (每日 due count 预测) │ 🔴 高                  │
├───────────────────┼──────────────────────────────┼────────────────────────┤
│ 未学新词队列      │ 列表 (next 50 by sortOrder)  │ 🔴 高                  │
├───────────────────┼──────────────────────────────┼────────────────────────┤
│ 进度条 + 完工预测 │ 已学/总数 + 估计完工日       │ 🔴 高                  │
├───────────────────┼──────────────────────────────┼────────────────────────┤
│ Mature 词分布     │ 直方图 (按 stability 区间)   │ 🟡 中                  │
├───────────────────┼──────────────────────────────┼────────────────────────┤
│ 失败次数 top 10   │ 列表                         │ 🟡 中 (Stats 页更合适) │
└───────────────────┴──────────────────────────────┴────────────────────────┘
```
```sh
# 完整规划:
各 tab 的明确职责:
- Today = "今天我要干什么" — 含两列预览 + quick actions
- Plan = "我的整个学习蓝图" — workload 预测 + new word queue + due backlog
- Library = "全部词库浏览" — search/filter, 进 WordDetail
- Flashcard / Typing = 学习模式
- Stats = "我学得怎么样" — 已有 Dashboard

# P1. Today 页 — 两列完整列表

┌──────────────────────────────────────────────────────────────┐
│  Good evening!                                              │
│  Friday, May 30                                              │
│                                                              │
│  [Book▾ GRE Core 500 ────]                                   │
│                                                              │
│  ✓ Learned 234   ↻ Due 12   + Remaining 266                 │
│                                                              │
│  Progress ━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━━ 47%                │
│                                                              │
│  [ Start Learning ]   [ Review Due ]   [ Type Practice ]    │
│                                                              │
│  ─────────────────────────────────────────────────────────  │
│                                                              │
│  ┌─ Reviews (12) ──────────┐  ┌─ New (10) ───────────────┐ │
│  │ ● aberrant      2d late │  │ ◯ obstreperous           │ │
│  │   adj 异常的             │  │   adj 吵闹的, 难以控制的    │ │
│  │ ● coalesce      1d late │  │ ◯ perfidious             │ │
│  │   v 联合, 合并            │  │   adj 背信弃义的           │ │
│  │ ● equivocate    today   │  │ ◯ quintessence           │ │
│  │   v 含糊其辞             │  │   n 精华                  │ │
│  │ ● garrulous     today   │  │ ◯ recalcitrant           │ │
│  │   adj 啰嗦的             │  │   adj 顽抗的             │ │
│  │ ⋯ scroll for more       │  │ ⋯ scroll for more        │ │
│  └─────────────────────────┘  └──────────────────────────┘ │
│                                                              │
│  💡 AI Tip: "criticism" 簇本周正确率 68%, 建议先复习         │
└──────────────────────────────────────────────────────────────┘

交互细节

- 行高紧凑 (~36px/行), spelling + 第一个中文 def
- 行点击 → popover 显示完整 detail (复用 WordPopoverView)
- 行右键 → "Skip today" / "Suspend" / "Open detail"
- 列内部独立滚动 (不影响外层)
- "due" 列显示距离 due 的相对时间 ("today" / "1d late" / "tomorrow")
- 顶部 stats 简化为一行 inline (释放屏幕)
- AI Tip 是 stretch goal, 接 BackgroundAI 异步生成

# Library
┌──── Library ────────────────────────────────────────────────┐
│ [🔍 Search ____________]  [Book▾] [Tier▾] [State▾] [Sort▾]  │
│                                                              │
│  C aberrant   /æbˈer.ənt/   adj 异常的       💡   Review    │
│  C coalesce   /ˌkoʊ.əˈles/  v   联合, 合并        Learning  │
│  M equivocate /ɪˈkwɪv.ə/    v   含糊其辞    💡   Review    │
│  ⋯                                                           │
│                                                              │
│  Showing 200 of 13,422 · [ Load More ]                      │
└──────────────────────────────────────────────────────────────┘

- 搜索框: TextField + 300ms debounce → SQL LIKE
- "Load More" 按钮 (而不是 infinite scroll, 简单可靠)
- Cell 右侧的小角标显示卡片状态 (颜色编码)
- 点击 row → WordDetailView (用 wordId 重新 fetch full word)

# P3. WordDetail — Learning Progress + 用户 mnemonic 编辑

┌─────────────────────────────────────────────────────────┐
│  aberrant  /æˈber.ənt/                       [Edit ✎]   │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                          │
│  Learning Progress                                       │
│  ┌────────────────────────────────────────────────────┐ │
│  │ State [Review]   Next due: in 3 days                │ │
│  │ Reps 8 · Lapses 1 · Accuracy 87%                    │ │
│  │ Stability 12.4d · Difficulty 5.8                    │ │
│  │                                                      │ │
│  │ Recent: ✓Good · ✓Good · ✗Again · ✓Good · ✓Easy    │ │
│  │         May 28   May 26   May 21    May 15  Apr 30  │ │
│  │                                                      │ │
│  │ [Reset progress]  [Suspend]                          │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                          │
│  Definitions                                             │
│  [adj] 偏离正常的; 异常的                                 │
│        departing from the expected or normal            │
│                                                          │
│  Examples                                                │
│  " The aberrant results prompted researchers to redo... │
│                                                          │
│  Mnemonics                                  [+ Add yours] │
│  💡 ab(离开) + err(犯错/走偏) → 走偏了 → 异常的          │
│  💡 (你写的) "ab错(error)了, 不正常" — May 30          ✎ │
│                                                          │
│  Synonyms · Word Roots · Info                            │
│                                                          │
│  Books: GRE Core 500 (#234) · My weak words             │
└──────────────────────────────────────────────────────────┘

关键交互

- Recent reviews 一行展示: ✓✓✗✓✓ 颜色块, hover 显示日期
- Reset progress: 弹确认, 删除 reviewCard + 让 word 回到 New
- Suspend: 不再 due, 在 Library 用 filter 找回
- + Add yours: 弹小 sheet, 用户输自己的助记
- 用户 mnemonic 显示作者: AI 写的 vs 用户写的视觉区分 (用户的可编辑, 有 ✎)
- Books 行: 显示该词在哪些 wordList 里
```
1. " Today 页删除现有的 "All caught up!" 卡片? ", 合理的, 信息密度尽可能高
2. " Reset progress / Suspend 在 WordDetail 是否需要?" 是的先不加
3. "Plan tab 里的 chart 用 Swift Charts 还是手画? " 使用原生的吧
4. sidebar 顺序: Today / Plan / Flashcard / Typing / Library / Stats 合理的
- 之前提到 "user_mnemonics", 我觉得也是合理的, 后续加上用户笔记的功能
```sh
推荐: user_content 表 (单表 + type 列)

CREATE TABLE user_content (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wordId TEXT NOT NULL REFERENCES word(id) ON DELETE CASCADE,
    type TEXT NOT NULL,         -- 'mnemonic' | 'note' | (future: 'example', 'link')
    content TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
);
CREATE INDEX idx_user_content_word ON user_content(wordId, type);
```

'WordSummary' 数据通路分叉是什么意思?
```sh
# 引入 WordSummary 后 (两条通路)
SQLite word table
    ├─ SELECT id, spelling, phonetic, frequency, json_extract(data, '$.definitions[0]')
    │  ↓
    │  WordSummary (轻量, ~7 字段)
    │  ↓
    │  LibraryView 列表行
    │
    └─ SELECT data (full BLOB)
       ↓ JSONDecoder
       Word struct (完整)
       ↓
       StudyView / WordDetailView / WordPopoverView
```
我觉得 WordSummary 的实现是有必要的, Library 已经有点卡了! 帮我完整实现一下!
自主安排进度, git commit, 将上面我们讨论的内容都实现一下

"WordDetail" 页面如何展开? 我好像看不到
可以了! 另外 console 中日志如下, 有问题吗?
```sh
没做 (按之前讨论 deferred)
- WordDetail Reset progress / Suspend 按钮 (v2 admin sheet)
- WordDetail 全字段 admin edit (full edit sheet)
- Plan workload "click bar → drill into that day"
- 用户 notes 功能 (UI, 但 schema 已就位)
```

1. WordDetail 页面目前是 "附加在某一 tab 上的", e.g. plan/library 页面点击一个单词; 
  1. 目前只能通过鼠标点击左上角按钮返回, 我感觉可以用 `esc` 来退出该页面? (或者 space toggle)
  2. 另外, 在 Library 页面, 能不能有个 "键盘操作" 的体验 (痛点是目前)? 通过上下来选择某个词, space toggle 显示词义, 方便我快速查看单词列表? (这个需求是否是伪命题?)
2. WordDetail 和 popover 的单词也的差异是什么?
  1. 我理解后者是 "单词速查" 快速检查某一单词? 但两者是否有必要区分?
  2. 交互逻辑上, 目前 popover 是不是还没有什么快捷键绑定? 
    1. 有个痛点是, 我在 flashcard/typing 页面点击某一单词之后, 预期用 `esc` 退出 popover 窗口 (回到上一步的状态, e.g. 继续背单词); 但目前会直接触发 flashcard 页面对于 esc 的操作 -- 中断学习. 这样的体验有点奇怪
```sh
# 根本差异:
┌──────────┬───────────────────────────────────┬─────────────────────────────────────┐
│   维度   │              Popover              │             WordDetail              │
├──────────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 触发场景 │ 阅读中遇到不认识的词, 想 "瞄一眼" │ 主动管理这个词 (查进度, 加助记)     │
├──────────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 滞留时间 │ < 5 秒                            │ 30 秒 - 几分钟                      │
├──────────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 信息密度 │ 核心义项 + 1 例句 + 1 助记 +      │ 全字段 + Learning Progress +        │
│          │ 同义词                            │ 编辑能力                            │
├──────────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 可编辑?  │ 否                                │ 是 (mnemonic)                       │
├──────────┼───────────────────────────────────┼─────────────────────────────────────┤
│ 退出     │ Esc / 点外                        │ Esc / Cmd+[                         │
└──────────┴───────────────────────────────────┴─────────────────────────────────────┘
```

## fix bugs
反馈问题:
1. 目前 popover 页面无法通过 esc 退出, 在该状态时所有键盘操作都失效了!
2. 可能关联的问题是: 目前在 typing 页面 space toggle 单词页之后, 再按 space 无法回去了! 也是所有快捷键失效!
3. 关于 WordDetail
  1. 在 Plan 页面进入全屏的 detailed 页面之后, 无法 esc 退出!
  2. 在 popover 页 "Open in Library" 之后, 当前的 workflow 被打断了! 无法快捷退出; 当前的 typing section 也被停止了!
console 日志如下供参考
```sh
# 重新设计
1. 键盘 Esc 用 "隐藏 Button + .keyboardShortcut(.escape)" — 不依赖焦点, 100% 可靠.
2. KeyCaptureView 不再静默丢事件 — 只是在 popover 期间不抢回焦点.
3. "Open in Library" 改为 "Show details" + sheet — 不切 tab, Typing session 不被打断, Esc 退 sheet 即可.
```
```sh
# 请你试一下这些场景:
1. Typing 页 Space toggle 单词 — 应该能正常 toggle 回去
2. Flashcard 弹 popover → Esc → 只关 popover, flashcard 不暂停
3. Plan 进 detail → Esc → 退栈
4. Typing 弹 popover → Cmd+O → 弹 sheet, Typing 不停止, Esc 关 sheet 后继续打字
5. Library 分屏选词 → Esc 清空选中, 不退 tab
```
可以了! 更新 specs 文件; 创建 done issue 记录
