
## feat: AI
我们之前实现了 Erudite 的基础能力, 包括 FSRS 的背单词体系, typing 形式的单词肌肉记忆, dictionary 能力.
参见 @.ea/spec/README.md
后续我的觉需要引入的核心能力是 AI -- 陪伴式的背单词助手, 帮我想一下其形式. 我的初步想法:
- AI 陪伴: 它能够理解你的需求, 随着你共同学习进步 (context aware).
- feat: memory, 因此, 它应该能够记得历史的对话/你学习的内容等信息.
- feat: 帮助单词背诵, e.g. 对于你经常拼错/标记 again/hard 的单词, 生成一些说明来帮助我记忆;
  - 交互: 例如我下一词 flashcard 的时候, AI 生成的内容会显示出来, 帮我辅助记忆
- feat: 应该有一个常驻 chat 页面, 你随时可以和它对话
- feat: 一个好的用户体验是, 类似 CC coding pet, 在你使用的时候能够有一些小 tips
  - 交互: 定时pop一小段文字, 内容包括不限于学习方法提醒, 当前进度汇报, 单词记忆技巧, etc
- context: 如何在背诵/typing 的时候, 引入合理的 context?
- 工具设计: 这样的 agent 应该支持调用工具来获取 user 当前的状态, 应该如何封装?
- 实现维度, 感觉可以参考 openclaw/hermes/claude-code 那种? coding-agent 整体发展比较成熟了; 但需要考虑如何在本应用中实现.
```sh
# 对比 Claude Code 和 Erudite AI
┌──────────────┬───────────────────────────┬──────────────────────────────────┐
│  Dimension   │        Claude Code        │            Erudite AI            │
├──────────────┼───────────────────────────┼──────────────────────────────────┤
│ Runtime      │ Node.js process           │ Swift (in-app)                   │
├──────────────┼───────────────────────────┼──────────────────────────────────┤
│ LLM          │ Claude API                │ Claude API (same)                │
├──────────────┼───────────────────────────┼──────────────────────────────────┤
│ Tools        │ Bash, Read, Write, LSP    │ DB queries, FSRS state, word ops │
├──────────────┼───────────────────────────┼──────────────────────────────────┤
│ Memory       │ CLAUDE.md + git           │ SQLite (observations table)      │
├──────────────┼───────────────────────────┼──────────────────────────────────┤
│ Context      │ File contents + git state │ Learning state + word data       │
├──────────────┼───────────────────────────┼──────────────────────────────────┤
│ Proactive    │ None (reactive only)      │ Event-driven tips                │
├──────────────┼───────────────────────────┼──────────────────────────────────┤
│ Conversation │ Multi-turn in terminal    │ Multi-turn in panel              │
├──────────────┼───────────────────────────┼──────────────────────────────────┤
│ Streaming    │ Yes (terminal)            │ Yes (SwiftUI Text)               │
└──────────────┴───────────────────────────┴──────────────────────────────────┘

# 不同于 Coding Agent 的关键差异
1. 成本敏感度更高：背单词是高频操作（一天可能翻 50-100 张卡），不能每张卡都 API call
2. 延迟敏感：卡片翻转是 <100ms 交互，AI 生成不能阻塞
3. Proactive 需求：Coding agent 是纯 reactive，Erudite 需要主动行为
4. 长期记忆更重要：Coding agent 每个 session 独立，Erudite 需要跨 session 的学习者建模

推荐的实现分层

Layer 0: AIProvider (API abstraction, streaming)
         ↓
Layer 1: AgentRuntime (tool loop, message management)
         ↓
Layer 2: MemoryStore (observation CRUD, profile, compression)
         ↓
Layer 3: ContextBuilder (per-mode context assembly)
         ↓
Layer 4: ProactiveEngine (event → trigger → generate)
         ↓
Layer 5: UI Integration (ChatPanel, TipBubble, InlineHint)

#  推荐的实现顺序
┌───────┬────────────────────────────────────────────┬────────────────────────────┐
│ Phase │                    What                    │         Why First          │
├───────┼────────────────────────────────────────────┼────────────────────────────┤
│ P0    │ AIProvider + AgentRuntime + basic chat UI  │ 核心能力，其他都依赖它     │
├───────┼────────────────────────────────────────────┼────────────────────────────┤
│ P1    │ Tool system (read-only tools: stats, word  │ Chat 有用的前提            │
│       │ history)                                   │                            │
├───────┼────────────────────────────────────────────┼────────────────────────────┤
│ P2    │ Memory system (observations + profile)     │ 跨 session 连续性          │
├───────┼────────────────────────────────────────────┼────────────────────────────┤
│ P3    │ Flashcard inline tips (pre-generated)      │ 第一个"AI 真正有用"的      │
│       │                                            │ moment                     │
├───────┼────────────────────────────────────────────┼────────────────────────────┤
│ P4    │ Proactive engine (event-driven tips)       │ "Coding pet" 体验          │
├───────┼────────────────────────────────────────────┼────────────────────────────┤
│ P5    │ Full context integration (typing/quiz      │ 全场景覆盖                 │
│       │ modes)                                     │                            │
└───────┴────────────────────────────────────────────┴────────────────────────────┘
```
```sh
· AI Companion 的 UI 形态你更倾向哪种？（这决定了 SwiftUI 布局方式和交互模式） → Side Panel (固定右侧)
· Memory 的实现复杂度你想要哪个级别？（影响初期开发量和 AI 的'聪明'程度） → Hybrid (渐进式)
· LLM 调用策略上，proactive tips 你更倾向？ → 混合策略 (推荐)
```

选型上的一个讨论
- 我发现 swift 的 ai/agent 生态似乎相对薄弱? anthropic/openai 都没有封装 sdk, 整体生态似乎没有 ts/py 好, 如果用 swift 开发是否会增加复杂度?
- 之前为什么用了 claude api 而非 openai? 两者有什么差异?

明白, 这样的话, 
- 相当于纯自主实现一个 ai agent 组件, 优势是整体上更加可控;
- 但这样整体的效果取决于我们的实现是否合理, 可能需要考虑很多因素, 需要做好 tracing 方便 debug, 可参考一些优秀设计.
架构上, 这个 feature 是否需要独立成一个包? 或者是否有一些开源实现呢?

我感觉这些项目都不是很成熟, 倾向于全部都自己实现, 更为可控.
确认没疑问的话, 开始分阶段实现
```sh
使用方式
1. 在 Config.json 中设置 aiApiKey 为你的 Anthropic API key
2. 启动 app → 右侧自动显示 AI panel
3. ⌘. 切换面板显示/隐藏
4. 输入问题 → AI 会自动调用 tools 查询你的学习数据并回复

后续 (P1/P2)
- P1: Memory system — observations table + user profile + 跨 session 记忆
- P2: Proactive tips — 事件驱动 (word shown / rating given) + tip cache + 节流
- P3: Flashcard 深度集成 — card back inline tips + "Ask AI" 按钮
```
应该支持使用非官方的 api url, 给用户配置
我配置好了 LLM 服务, 可以独立测试吗?
总结一下当前的实现
```sh
P0 AI Companion 实现总结

架构
┌─────────────────────────────────────────────────────────────────┐
│ EruditeApp                                                       │
│  └─ ContentView (HStack)                                        │
│       ├─ NavigationSplitView (sidebar + detail)  ← 已有功能     │
│       └─ AIChatPanel (280pt, 可 ⌘. 切换)        ← 新增         │
│            └─ ChatViewModel                                      │
│                 └─ AgentRuntime (agent loop)                     │
│                      ├─ AnthropicClient (HTTP + SSE)             │
│                      ├─ ToolRegistry (4 tools)                   │
│                      └─ SystemPrompt (context builder)           │
└─────────────────────────────────────────────────────────────────┘
┌───────────┬───────────────────────────────────────────────┬─────────────────────────────────────────────────┐
│    层     │                     文件                      │                      职责                       │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│ API       │ Services/AI/AnthropicTypes.swift              │ Messages API 全部 Codable 类型、JSONValue       │
│ Client    │                                               │ enum、StreamEvent                               │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Services/AI/SSEParser.swift                   │ SSE 行协议解析器 (处理 partial                  │
│           │                                               │ chunks、comments、multi-line data)              │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Services/AI/AnthropicClient.swift             │ HTTP 层: URLSession.bytes streaming,            │
│           │                                               │ Bearer/x-api-key 双认证                         │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│ Agent     │ Services/AI/AgentRuntime.swift                │ 核心 loop: messages→LLM→tool_use→execute→loop,  │
│           │                                               │ 流式输出                                        │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Services/AI/SystemPrompt.swift                │ Persona + tool 使用指令 + 当前 mode context     │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│ Tools     │ Services/AI/Tools/AITool.swift                │ Protocol + ToolRegistry + encodeToolResult      │
│           │                                               │ helper                                          │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Services/AI/Tools/GetUserStatsTool.swift      │ 总体学习统计 (learned/due/accuracy/streak)      │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Services/AI/Tools/GetWordHistoryTool.swift    │ 单词复习历史 (ratings breakdown, stability,     │
│           │                                               │ lapses)                                         │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Services/AI/Tools/GetWeakWordsTool.swift      │ 薄弱词列表 (按 lapses/stability 排序)           │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Services/AI/Tools/GetCurrentSessionTool.swift │ 当前 session 状态                               │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Services/AI/Tools/DatabaseService+AI.swift    │ DB 扩展: fetchCardForWord, fetchWeakCards,      │
│           │                                               │ fetchRecentAccuracy, fetchStudyStreak           │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│ UI        │ Views/AI/AIChatPanel.swift                    │ 右侧面板容器 (header + messages + suggestions + │
│           │                                               │  input)                                         │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Views/AI/ChatMessageView.swift                │ 消息气泡 (markdown 渲染, tool use 指示)         │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Views/AI/ChatInputView.swift                  │ 输入框 + send/cancel 按钮                       │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Views/AI/StreamingTextView.swift              │ 流式文本 + 闪烁光标                             │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ Views/AI/ThinkingIndicator.swift              │ 工具执行动画 ("Looking up weak words...")       │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│ ViewModel │ ViewModels/ChatViewModel.swift                │ UI state proxy (visibleMessages, isProcessing,  │
│           │                                               │ send/cancel)                                    │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│ 修改      │ Views/Main/ContentView.swift                  │ HStack 包裹 + AI panel + ⌘. 快捷键              │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ App/AppState.swift                            │ 添加 aiRuntime + static var shared              │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ App/EruditeApp.swift                          │ 初始化时设置 shared, 窗口宽度→1100              │
├───────────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────┤
│           │ App/AppConfig.swift                           │ 新增 aiBaseURL, aiModel, resolvedAIBaseURL,     │
│           │                                               │ resolvedAIModel                                 │
└───────────┴───────────────────────────────────────────────┴─────────────────────────────────────────────────┘
# 关键设计
┌────────────┬────────────────────────────────────────────────────────────────────────────────┐
│   设计点   │                                    实现方式                                    │
├────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ SSE 解析   │ 自研 struct, ~80 行, 处理 partial chunk / \r\n / comments                      │
├────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ Agent Loop │ messages→stream→accumulate text+tool_use→execute tools→append result→loop back │
├────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ 认证兼容   │ 官方 API 用 x-api-key + prompt caching; 代理用 Authorization: Bearer           │
├────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ Tool 执行  │ 同步调用 DatabaseService (GRDB 内部串行化, 线程安全)                           │
├────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ UI 响应式  │ AgentRuntime 是 @Observable, streamingText 变化直接驱动 SwiftUI 重渲染         │
├────────────┼────────────────────────────────────────────────────────────────────────────────┤
│ 安全上限   │ 每轮最多 5 次 tool call, 防止无限循环                                          │
└────────────┴────────────────────────────────────────────────────────────────────────────────┘
```

## bugfix
发现性能问题: 我测试聊天过程中, Erudite (18473) CPU 100+, 内存也炸了
```sh
核心问题是 byte-by-byte 迭代 — 每个字节都触发一次 async context switch，加上每个 token 都触发 SwiftUI re-render + markdown 重新解析。三个热点：
1. for try await byte in bytes — 逐字节遍历，极度低效
2. streamingText = accumulatedText 每个 token 都更新 → SwiftUI 每次重渲染整个 AttributedString(markdown:)
3. ThinkingIndicator 50ms interval 动画循环

问题: CPU 100%
原因: for try await byte in bytes 逐字节遍历，每个字节一次 async context switch
修复: 改用 bytes.lines — OS 层面缓冲，按行返回
────────────────────────────────────────
问题: 内存暴涨
原因: 每个 token 触发 streamingText = accumulatedText → SwiftUI 每次 re-render 时
  AttributedString(markdown:) 重新解析全文
修复: ① 50ms 节流（max 20次/秒）② streaming 时用 plain Text 不做 markdown 解析
────────────────────────────────────────
问题: 持续高 CPU
原因: ThinkingIndicator 用 50ms Timer 不断更新 rotation state
修复: 改用 SwiftUI .animation(.linear.repeatForever) 声明式动画，GPU 层处理
```
新 bug: 现在发消息似乎收不到返回了

## memory
显然上面的实现整理成一个 done issue, 然后讨论之前讨论的 memory 体系的实现
- 整体设计上, 你计划如何去做?
- 用户可以新开一个 session 的价值是什么? 如何实现多 session 的?
```sh
# Memory 整体设计
┌─────────────────────────────────────────────────────────────┐
│                    Memory Architecture                        │
│                                                              │
│  ┌── Working Memory (in-memory) ─────────────────────────┐  │
│  │ Current session messages (already have this in P0)      │  │
│  │ Lost on app restart                                     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌── Episodic Memory (SQLite) ───────────────────────────┐  │
│  │ conversation_sessions: id, title, summary, created_at  │  │
│  │ conversation_messages: session_id, role, content, ts    │  │
│  │ → 完整对话历史, 支持多 session 切换                     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌── Semantic Memory (SQLite) ───────────────────────────┐  │
│  │ observations: type, content, related_words, confidence │  │
│  │ user_profile: learning_style, weak_areas, preferences  │  │
│  │ → 从对话中提取的"认知"，注入每次 system prompt          │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

数据流

Chat Turn 结束
    │
    ├─→ Messages 持久化到 SQLite (episodic)
    │
    └─→ Observation 提取 (async, 用 Haiku)
         │
         └─→ 存入 observations 表 (semantic)
              │
              └─→ 下次对话时注入 system prompt

System Prompt 注入示例

## About this learner (from memory)
- 偏好 word-root 类型的记忆法, 不喜欢纯故事型
- 反复混淆 aberrant / abhorrent (已提醒3次)
- 拉丁词根类单词准确率低
- 每天平均学习 20 分钟, 晨间效率最高
- GRE 考试倒计时 45 天

## Recent conversation context
- 昨天讨论了 equivocate vs prevaricate 的区别
- 用户表示想加快新词进度
```

1. 整体设计上, 包括 work/episodic/semantic 的划分, 我感觉对于 chat 流程的建模是合理的! (后续 proactive agent 的设计再说)
2. Session 粒度: 我预期应该默认是继续上一个 session
3. Observation 提取时机: 1. 提取操作预期的输出是什么? 如何持久维护? 2. 感觉每个 turn 有点太频繁; "session 结束" 又不稳定 (因为用户可能一直开着对话); 甚至, 关闭app 的话如何处理?
4. memory 相关工具设计: 我理解 agent 也被允许读取更完整的历史记忆, 如何设计 tools?
5. 模型分层: 我感觉可以参考 CC 区分快/慢两个模型, 主模型参与对话, 快的 (e.g. kaihu) 负责标题生成, 补全词义等功能; 这两个模型可以放 config 里
```sh
┌───────────────────────────┬───────────────────────────┬───────────────────────────┬──────────────────────────┐
│           Tool            │           输入            │           输出            │         使用场景         │
├───────────────────────────┼───────────────────────────┼───────────────────────────┼──────────────────────────┤
│ recall_observations       │ query?: String, type?:    │ 相关 observations 列表    │ "我之前搞混了什么？"     │
│                           │ ObsType, limit?: Int      │                           │                          │
├───────────────────────────┼───────────────────────────┼───────────────────────────┼──────────────────────────┤
│ search_past_conversations │ query: String, limit?:    │ 过往 session 摘要列表     │ "我们之前聊过 equivocate │
│                           │ Int                       │ (title + summary + date)  │  吗？"                   │
├───────────────────────────┼───────────────────────────┼───────────────────────────┼──────────────────────────┤
│ get_conversation_detail   │ session_id: String,       │ 指定 session 的最近 N     │ 深入回顾某次对话         │
│                           │ recent_n?: Int            │ 条消息                    │                          │
├───────────────────────────┼───────────────────────────┼───────────────────────────┼──────────────────────────┤
│ save_observation          │ type, content,            │ 确认                      │ AI 主动记住某事          │
│                           │ related_words?            │                           │ ("我记住了")             │
└───────────────────────────┴───────────────────────────┴───────────────────────────┴──────────────────────────┘

P1 Memory 交付物:
├── Session 持久化 (消息不丢失, 默认继续上个 session)
├── 多 Session 管理 (新建/切换/列表 UI)
├── Observation 提取 (5轮/app后台时触发, Haiku执行)
├── System prompt 注入 (profile + recent observations)
├── Memory tools (recall_observations, search_past_conversations)
├── Auto-title (Haiku 生成 session 标题)
└── 模型分层 (Config 支持 aiModel + aiFastModel)
```
没问题, 直接开始实现
```sh
关键行为
1. App 启动 → 自动恢复上次 session 的消息
2. 每次 AI 回复完成 → 消息持久化 + 检查是否触发 observation 提取 (≥5轮) + 首次自动生成标题
3. App 后台/关闭 → flush 未提取的 observations
4. 新建 Session → 清空 runtime, 创建新 DB record
5. 切换 Session → 从 DB 加载历史消息, 恢复到 runtime
6. System Prompt → 每次请求自动注入 top observations
```

## feat: logging system
1. 在没配置 模型服务 / 缺少 aiFastModel 的时候是什么行为?
2. 模型报错的话如何 debug? 目前 Erudite 有什么日志系统吗?

我觉得重点是第二个 -- 需要从整体来设计一个 log 体系-- 因为系统的各个组件都需要记录 & debug
```sh
· 日志系统的范围你想要哪些？（可多选） → Apple os.Logger (Recommended), 额外写入本地文件, AI 调用 tracing (SQLite), In-app debug panel
```
```sh
# 日志系统总结
架构

┌─ 组件调用 ──────────────────────────────────────────────────┐
│  Log.ai.info("Stream started")                               │
│  Log.memory.error("Extraction failed", error: e)             │
│  Log.db.debug("Query took 12ms")                             │
└──────────────────────┬───────────────────────────────────────┘
                       │
              ┌────────▼────────┐
              │    ELogger      │ (per-category, thread-safe)
              └────────┬────────┘
                       │
         ┌─────────────┼─────────────┬──────────────┐
         ▼             ▼             ▼              ▼
   ┌──────────┐  ┌──────────┐  ┌─────────┐  ┌──────────┐
   │os.Logger │  │FileLogger│  │DebugLog │  │AITracer  │
   │(system)  │  │(daily    │  │(in-mem  │  │(SQLite   │
   │Console.app│  │rotation) │  │500 ring)│  │per-call) │
   └──────────┘  └──────────┘  └─────────┘  └──────────┘
```
```sh
# 使用方式
┌─────────────┬────────────────────────────────────────────────────────────────────────┐
│  查看方式   │                                如何访问                                │
├─────────────┼────────────────────────────────────────────────────────────────────────┤
│ Console.app │ 打开 Console.app → 过滤 site.easonsi.Erudite                           │
├─────────────┼────────────────────────────────────────────────────────────────────────┤
│ 本地文件    │ ~/Library/Application Support/Erudite/Logs/erudite-2026-05-28.log      │
├─────────────┼────────────────────────────────────────────────────────────────────────┤
│ In-app      │ ⌘⇧D 打开 Debug 窗口                                                    │
├─────────────┼────────────────────────────────────────────────────────────────────────┤
│ AI Traces   │ Debug 窗口 → "AI Traces" tab (按时间, 显示 model/tokens/latency/tools) │
└─────────────┴────────────────────────────────────────────────────────────────────────┘
```
将上面我们已经完成的工作 (AI 服务封装, 基础 chat 能力, log 体系) 记录为 issues, 并更新相关 specs 文件

## optim chat agent
对于 chat sidebar 使用反馈:
- UI 层面
  - 现在左侧(栏目列表)和右侧分别用的什么组件? 我希望能够自由拖动右侧 chat sidebar 的宽度
  - 对于一次工具调用, 我希望能够看到具体的调用参数 & 工具返回, 方便我 debug; UI 上默认折叠? 我点击展开
- 工具 & 实现优化
  - 问题: 我发了一句 "我们之前有哪些会话?" agent 多次调用 `search_past_conversations` 但是参数传入有问题, 连续 5 次之后直接 "(Stopped: reached tool call limit)"
  - 似乎是调用工具格式错误? 还是工具实现有问题?
  - 另一点优化: 1. tc limit 设置=10 调大一点; 2. 在达到上限之前, 是不是可以在系统中加一句提示 "请勿调用直接回复", 避免直接中断?

似乎有 bug: 
- 保存到DB中的 session 信息是不是没有 toolcall? 我发现恢复对话的话只能看到文本了!
  - session 存储, 应该把完整的信息都保存下来!
- 关于日志:
  - `PRODUCT_BUNDLE_IDENTIFIER = site.easonsi.Erudite` 我在系统 Console 中可以搜到;
  - 但似乎没找到额外的日志文件? 路径在哪里?

## setup session_id / request_id
1. 参考 Claude/ChatGPT 的设计, 每个 session / request 应该个 id? 会方便溯源?
  - search_past_conversations 返回 sid 也方便 agent 理解?
2. 在 chat 页面中:
  - 目前还是没法查看 tollcall 的入参和完整返回? 我想要到详细数据 (可以限制显示高度? 我理解数据量不大对于渲染应该性能影响不大?)
  - 每次模型请求应该会返回一些 token & usage 信息, 这些可以显示出来吗?
  - 模型请求返回的 header 里面是不是有 request-id? 这个也可以记录下来吗?

## fix performance issue
Erudite (35250) 这个进程, CPU 似乎炸了, 可以 debug 分析一下原因吗?
我重新试了一下, 还是卡住了, swift 性能那么差吗? js 生态似乎没有这种问题?
```sh
# 这不是 Swift 性能差 — 是 SwiftUI @Observable + ForEach + 计算属性 的一个经典陷阱：
ForEach(viewModel.visibleMessages)  ← 计算属性，每次创建新数组
    │
    ├─ SwiftUI 求值 body → 访问 visibleMessages → 创建 [ChatMessage]
    ├─ SwiftUI 对比上次结果 → 新数组 ≠ 旧数组 (不同实例)
    ├─ SwiftUI: "数据变了!" → 触发重新渲染
    ├─ 重新渲染 → 再次访问 visibleMessages → 又创建新数组
    └─ ∞ 无限循环 → CPU 100% + 内存无限增长

为什么 JS/React 没这个问题？ React 的 useMemo / 虚拟 DOM diff 是按 key 比较，不会因为引用不同就重新渲染。SwiftUI 的 @Observable 跟踪更激进 — 任何 observed property 被访问就建立依赖。

修复： 直接用 appState.aiRuntime?.messages（stored property，引用稳定）+ 在 ForEach 内部用 if !message.isToolResult 过滤，避免每帧创建新数组。
```
将这一问题&经验记录到 specs 体系中
```sh
已记录到 .ea/spec/development.md 的新章节 "SwiftUI + @Observable Performance Pitfalls"，包含：
1. 计算属性 + ForEach 无限循环 — 最核心的坑，附带正确/错误代码对比
2. onChange guard — 防止空闲时触发级联
3. streaming 时避免 markdown parse — 每帧开销
4. @Observable struct array identity — 底层原因分析
5. 调试方法 — sample 命令 + 关键指标识别
6. 安全模式速查表 — 所有场景的推荐 pattern
```

## fix toolcall parse?
总结目前设计的所有工具列表, 它们有哪些入参?
- 对于模型返回结果的解释是不是有点问题? 我尝试问了让 agent 调用 `get_word_history(portray)`, 但似乎每次工具调用都失败了
```sh
# 当前工具总览
┌───────────────────────────┬───────────────────────────────┬────────────────────────────────────────┐
│           Tool            │             入参              │                  作用                  │
├───────────────────────────┼───────────────────────────────┼────────────────────────────────────────┤
│ get_user_stats            │ (无)                          │ 总体学习统计:                          │
│                           │                               │ due/new/learned/accuracy/streak        │
├───────────────────────────┼───────────────────────────────┼────────────────────────────────────────┤
│ get_word_history          │ word: String (必填)           │ 单词复习历史: ratings, lapses,         │
│                           │                               │ stability, due date                    │
├───────────────────────────┼───────────────────────────────┼────────────────────────────────────────┤
│ get_weak_words            │ limit?: Int, sort_by?:        │ 薄弱词列表                             │
│                           │ "lapses"|"stability"          │                                        │
├───────────────────────────┼───────────────────────────────┼────────────────────────────────────────┤
│ get_current_session       │ (无)                          │ 当前学习 session 状态 (mode, book,     │
│                           │                               │ due)                                   │
├───────────────────────────┼───────────────────────────────┼────────────────────────────────────────┤
│ recall_observations       │ query?: String, type?:        │ 查询长期记忆 observations              │
│                           │ ObsType, limit?: Int          │                                        │
├───────────────────────────┼───────────────────────────────┼────────────────────────────────────────┤
│ search_past_conversations │ query?: String, limit?: Int   │ 搜索/列出历史会话                      │
└───────────────────────────┴───────────────────────────────┴────────────────────────────────────────┘
```
// 确认是 API 问题

## optim chat ui
我切换了openrouter 确保正确, 现在能正确调用了!
下面来对前端优化:
- sidebar 可拖拽之后, 遮挡了原本最上面的边线? 原本那根横向的分割线中断了, 而最下面的输入框上面的横线两侧也是空白的, UI 有点奇怪.
- 工具调用详情展开后, 输入参数下面有很大的空白? 为什么
- 输入框聚焦: 预期是点击 chat 页面 (没有其他操作的话), 我键盘输入就应该能够输入文本到输入框了, 但现在只能点击最下面的输入框之后, 才能开始输入; 而且流式输出之后还得重新点一次, 体验不好
```sh
┌──────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│       问题       │                                       修复                                       │
├──────────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│                  │ 去掉了 drag handle 的独立 Rectangle + Divider 双元素，改为 Divider               │
│ 分割线中断/空白  │ 上叠加透明拖拽区域 (.overlay)；去掉了 panel 的 frame(minWidth:260...)            │
│                  │ 让它自然填充                                                                     │
├──────────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│ 工具详情空白区域 │ ScrollView(.vertical).frame(maxHeight: 60/100) 改为直接 Text +                   │
│                  │ fixedSize(horizontal: false, vertical: true) —— 内容短就紧凑，不预留空间         │
├──────────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│ 输入框不自动聚焦 │ 添加 shouldFocus 参数 + onAppear { isFocused = true } + onChange(of:             │
│                  │ shouldFocus) —— panel 出现时自动聚焦，streaming 结束后重新聚焦                   │
└──────────────────┴──────────────────────────────────────────────────────────────────────────────────┘
```
继续优化输入体验:
1. 键盘输入: 在我鼠标检查 (包括上下滚动, 划区选择) 的时候, 键盘输入都应该放到输入参数中, 而不是我打字了没反应! -- 参考 Claude.app 的设计;
2. 同时, 在流式数据过程中, 我也应该可以打字 (编辑下一条指令) (而非无法键入状态), 只是不能发送 (需要点击停止之后才能发送)
3. 允许多行: shift+enter 换行; enter 发送

## keyboard / focus model
关于快捷键
- 现在我在鼠标点击 sidebar 的历史对话的时候, 键盘输入似乎没反应
- 我鼠标点击左侧的菜单区域 (e.g. "Stats" 按钮或者空白区域), 再键入 T/F/L/S 会自动跳转到那个 tab 上, 这个是 swift 组件的特性?
- 类似这个逻辑的话, 我是不是可以加一个全局快捷键 (类似 Claude.app 通过两次 option 按键唤醒全局 chat 快捷输入): 在不冲突的情况下, 设置 `/` 快速进入 chat sidebar -- 作为 AI 的一个入口?
```sh
# 快捷键总览：
┌─────────────┬──────────────────────────┬─────────────────────────────────────────────────┐
│   快捷键    │           作用           │                      场景                       │
├─────────────┼──────────────────────────┼─────────────────────────────────────────────────┤
│ /           │ 打开 AI panel + 聚焦输入 │ Today/Library/Dashboard (不在 Flashcard/Typing) │
├─────────────┼──────────────────────────┼─────────────────────────────────────────────────┤
│ ⌘.          │ 切换 AI panel 显示/隐藏  │ 全局                                            │
├─────────────┼──────────────────────────┼─────────────────────────────────────────────────┤
│ Enter       │ 发送消息                 │ Chat 输入框聚焦时                               │
├─────────────┼──────────────────────────┼─────────────────────────────────────────────────┤
│ Shift+Enter │ 换行                     │ Chat 输入框聚焦时                               │
├─────────────┼──────────────────────────┼─────────────────────────────────────────────────┤
│ ⌘⇧D         │ 打开 Debug 面板          │ 全局                                            │
└─────────────┴──────────────────────────┴─────────────────────────────────────────────────┘
```

1. ⌘. 进入, 或者点击右上角打开 chat 的时候, 默认就应该可以是输入了呀? 现在不行
2. 澄清一下, 不是 "Session list 点击后失效" -- 而是我在点击上面的 chat 历史的时候 (e.g. 点击了agent 输出的部分/工具调用, 或者空白区域), 鼠标输入没有自动放到输入框中, 这个体验不是很好

为什么不能在 "Flashcard/Typing" 状态通过 `/` 进入聊天?
- 我觉得是有需求的? 比如我记不住某个单词的时候, 询问 AI 记忆方法;
- 而且, 此时进入 chat 页面, 应该是附带 context 信息的 -- agent 应该能感知到我当前在记忆的单词 (当前, 我处于其他页面的时候, 它应该也能简单了解我的情况, 参考 Cursor 中 agent 能知道我打开的文件, CC 中 agent 知道我的操作系统)
bugfix: 目前自动聚焦的能力似乎消失了, 能够 debug 吗? 深入分析定位问题

我感觉还是有问题:
1. 点击输入框之后, 无法点击回到右边的 flashcard/typing 页面了 -- 我感觉左右应该是两个区域, 我点击哪个区域之后, 就应该聚焦在哪里 -- 所以点击左侧 flashcard 部分的空白区域后, 我应该能继续用键盘来操作背单词;
3. 上面提到的 "点击右侧 chat 栏的对话历史的时候 (e.g. 点击了agent 输出的部分/工具调用, 或者空白区域), 鼠标输入没有自动放到输入框中" 的问题仍存在! -- 和 1 一样的逻辑, 我预期我点击右侧预期的时候, 可以方便的键盘输入
2. `/` 是变成全局捕获了吗? 带来的问题是我没法在输入栏输入它了! -- 我感觉它应该像 `⌘.` 一样作为一个触发快捷键? 或者直接删掉? 目前他俩逻辑好像是一样的

还是不对:
- 在 点开侧边栏/⌘. 打开之后, 输入的按键仍然没有进入到输入框!
- 同样的, 我点击当前 session 的对话内容, 仍然无法输入!
- 另外, `⌘.` 的含义是 toggle 侧边栏; 那么我在 flashcard/typing 状态, 同时打开侧边栏的时候, 如何快速进入 "chat 输入状态" 呢?
系统的构思一下方案, 先不着急实现, 跟我分析一下
```sh
# 根因: KeyCaptureView 是一个 NSView，设计为永远抢占 firstResponder：
这就是为什么 TextEditor 无法获得焦点 — 即使你点击了 TextEditor（它底层是 NSTextView），KeyCaptureView 的 resignFirstResponder 检查了 current is NSTextView 应该让步。但问题是：

1. isActive: appState.selectedTab == .flashcard — 当用户在 Flashcard tab 时，KeyCaptureView 是 active 的
2. 它的 resignFirstResponder 在让出后又抢回 — 虽然有 NSTextView 检查，但 SwiftUI 的 TextEditor focus 机制不走 AppKit 的 makeFirstResponder 路径（@FocusState 是 SwiftUI 层面的）

核心冲突

KeyCaptureView (NSView层)           TextEditor/@FocusState (SwiftUI层)
    │                                        │
    ├─ window.makeFirstResponder(self)      ├─ isFocused = true
    ├─ resignFirstResponder → re-grab       ├─ 底层是 NSTextView
    │                                        │
    └─ 两者在不同层级竞争 firstResponder ──────┘

SwiftUI 的 @FocusState 设置 isFocused = true 后，底层尝试让 TextEditor 的 NSTextView 成为 firstResponder。但 KeyCaptureView 的 resignFirstResponder 立即又抢回来了。

虽然有 if current is NSTextView { return } 这个让步逻辑，但时序问题：
- SwiftUI 设置 focus → AppKit 尝试 makeFirstResponder(NSTextView)
- KeyCaptureView.resignFirstResponder 被调用
- 此时 window.firstResponder 可能还没变成 NSTextView（异步调度）
- KeyCaptureView 重新抢回

# 方案

┌─────────────────────────┬────────────────────────────────────────────────┬──────────────────────────────┐
│          方案           │                      描述                      │            优缺点            │
├─────────────────────────┼────────────────────────────────────────────────┼──────────────────────────────┤
│ A: 让 KeyCaptureView    │ 当 AI panel 可见且用户意图输入 chat            │ 简单，但需要一个信号通道     │
│ 感知 chat panel         │ 时，disable KeyCaptureView                     │                              │
├─────────────────────────┼────────────────────────────────────────────────┼──────────────────────────────┤
│ B: Chat 输入也用 NSView │ 放弃 SwiftUI TextEditor，用                    │                              │
│  层                     │ NSViewRepresentable 的 NSTextView 来做 chat    │ 彻底解决层级冲突，但代码量大 │
│                         │ 输入                                           │                              │
├─────────────────────────┼────────────────────────────────────────────────┼──────────────────────────────┤
│ C: 给 KeyCaptureView    │ 在 resignFirstResponder 的检查中，不只检查     │ Hack，脆弱                   │
│ 加"对手"检测            │ NSTextView，还检查 panel 是否在 focus 区域     │                              │
└─────────────────────────┴────────────────────────────────────────────────┴──────────────────────────────┘
```
NSView层 SwiftUI层 有什么区别?
```sh
# 核心概念
一个窗口只有一个 firstResponder — 这是 AppKit (NSView 层) 的规则。所有键盘事件都发给这个唯一的 view。

┌──────────┬──────────────────────────────────────────┬────────────────────────────────────┐
│          │                SwiftUI 层                │          AppKit/NSView 层          │
├──────────┼──────────────────────────────────────────┼────────────────────────────────────┤
│ 焦点模型 │ @FocusState — 声明式, 可以多个 "focused" │ window.firstResponder — 全窗口唯一 │
├──────────┼──────────────────────────────────────────┼────────────────────────────────────┤
│ 键盘事件 │ .onKeyPress — SwiftUI 分发               │ keyDown(with:) — 直接回调          │
├──────────┼──────────────────────────────────────────┼────────────────────────────────────┤
│ 控制力   │ 不能直接 makeFirstResponder              │ 完全控制 responder chain           │
├──────────┼──────────────────────────────────────────┼────────────────────────────────────┤
│ 底层实现 │ SwiftUI 的 TextEditor 底层是 NSTextView  │ 直接就是 NSView                    │
└──────────┴──────────────────────────────────────────┴────────────────────────────────────┘
```
从 first principle 出发, Erudite app 整个的窗口设计模型应该是怎样的? 怎么是更好的开发模式? 是否需要重构?
```sh
# 问题本质
┌──────────────────┬────────────────────────────┬────────────────────────────────┬───────────────────────┐
│       区域       │          键盘需求          │            实现方式            │         问题          │
├──────────────────┼────────────────────────────┼────────────────────────────────┼───────────────────────┤
│ Sidebar (List)   │ type-to-select (T/F/L/S)   │ AppKit 自带                    │ 和 KeyCaptureView     │
│                  │                            │                                │ 冲突                  │
├──────────────────┼────────────────────────────┼────────────────────────────────┼───────────────────────┤
│ Flashcard/Typing │ 全键盘操作                 │ KeyCaptureView (NSView,        │ 设计就是"永远抢回来"  │
│                  │ (Space/1234/字母)          │ 强制抢)                        │                       │
├──────────────────┼────────────────────────────┼────────────────────────────────┼───────────────────────┤
│ AI Chat          │ 文本输入                   │ TextEditor + @FocusState       │ 抢不过 KeyCaptureView │
│                  │                            │ (SwiftUI)                      │                       │
└──────────────────┴────────────────────────────┴────────────────────────────────┴───────────────────────┘
```
KeyCaptureView 这一层抽象的作用是什么? 有必要吗? NSViewRepresentable 和 View 的差异是什么? 是否有更主流的开发规范?
```sh
 macOS 上 SwiftUI 的 @FocusState + .onKeyPress 有以下已知问题：

┌────────────────┬──────────────────────────────────────────────────────┐
│      问题      │                         表现                         │
├────────────────┼──────────────────────────────────────────────────────┤
│ Popover 偷焦点 │ 弹出 popover → 关闭 → 焦点丢失, .onKeyPress 不再响应 │
├────────────────┼──────────────────────────────────────────────────────┤
│ Button 偷焦点  │ 点击评分按钮 → 焦点移到按钮 → 后续键盘无响应         │
├────────────────┼──────────────────────────────────────────────────────┤
│ System beep    │ SwiftUI 未处理的 key event → 系统发出 "bonk" 警告音  │
├────────────────┼──────────────────────────────────────────────────────┤
│ 不确定性       │ .onKeyPress 有时响应有时不响应, 取决于 focus state   │
└────────────────┴──────────────────────────────────────────────────────┘

所以 KeyCaptureView 用 NSView 层直接拦截 keyDown，绕过 SwiftUI 的 focus 系统。

NSViewRepresentable vs View

┌─────────────────────────────────────────────────────────────────┐
│                                                                   │
│  SwiftUI View (struct, 声明式)                                    │
│  ├─ 优点: 简洁, 声明式, 自动 diff                                 │
│  ├─ 缺点: 不能直接控制 AppKit 底层行为                            │
│  └─ 适用: 99% 的 UI 场景                                         │
│                                                                   │
│  NSViewRepresentable (桥接 AppKit)                                │
│  ├─ 优点: 完全控制 NSView 生命周期, responder chain, events       │
│  ├─ 缺点: 打破 SwiftUI 声明式模型, 手动管理状态                   │
│  └─ 适用: SwiftUI 做不到的事 (自定义键盘, Metal, 底层 text rendering)│
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

KeyCaptureView 用 NSViewRepresentable 是因为：
1. 需要 override keyDown — SwiftUI 没有等价 API
2. 需要 override resignFirstResponder — 防止焦点丢失
3. 需要 suppress system beep — SwiftUI 无法做到
4. 需要 hitTest → nil — 让鼠标穿透到底下的 SwiftUI 按钮
```
```sh
# 看看其他 macOS SwiftUI app 怎么处理：

┌──────────────────────┬──────────────────────────────────────┬──────────────────────────────┐
│         App          │                 方式                 │             场景             │
├──────────────────────┼──────────────────────────────────────┼──────────────────────────────┤
│ Apple Notes          │ 纯 SwiftUI .onKeyPress               │ 简单快捷键, 不需要"永远响应" │
├──────────────────────┼──────────────────────────────────────┼──────────────────────────────┤
│ Xcode                │ AppKit 为主, SwiftUI 嵌入            │ 编辑器完全是 NSTextView      │
├──────────────────────┼──────────────────────────────────────┼──────────────────────────────┤
│ Things 3             │ AppKit + NSViewRepresentable         │ 键盘驱动的 task 操作         │
├──────────────────────┼──────────────────────────────────────┼──────────────────────────────┤
│ qwerty-learner (web) │ document.addEventListener('keydown') │ 类似我们的需求               │
└──────────────────────┴──────────────────────────────────────┴──────────────────────────────┘
```
明白, 帮我优化一下
