
# Erudite


## fast qa -- FSRS
继续快问快答: 1. 目前 Today 页的 Start Learning/Review Due/New words 分别是什么意思?
```sh
# 代码
  ┌────────────────┬────────────────┬──────────────────────────────────┬──────────────────────────────────┐
  │      按钮      │ StudyQueueMode │             查询逻辑             │               含义               │
  ├────────────────┼────────────────┼──────────────────────────────────┼──────────────────────────────────┤
  │ Start Learning │ .mixed         │ due cards + new cards (limit 10) │ 混合模式：先复习到期的，再学新词 │
  ├────────────────┼────────────────┼──────────────────────────────────┼──────────────────────────────────┤
  │ Review Due     │ .reviewOnly    │ state != 0 AND dueDate <= now    │ 只复习：已学过且到期需要巩固的   │
  ├────────────────┼────────────────┼──────────────────────────────────┼──────────────────────────────────┤
  │ New Words      │ .newOnly       │ state = 0 (limit 20)             │ 只学新词：从未见过的卡片         │
  └────────────────┴────────────────┴──────────────────────────────────┴──────────────────────────────────┘

# FSRS 卡片状态流转
  New (state=0) ──学习──→ Learning (state=1) ──记住──→ Review (state=2)
                                                           │
                                                       忘记了
                                                           ↓
                                                     Relearning (state=3)
                                                           │
                                                        重新记住
                                                           ↓
                                                     Review (state=2)

  - New: 从没见过，等着被 "Start Learning" 或 "New Words" 拉出来
  - Due: Learning/Review/Relearning 中 dueDate <= 现在 的卡片，需要复习
```

FSRS 算法逻辑是怎样的? 1/2/3/4 (again/hard/good/easy) 代表什么意思? 每天安排的复习/学习逻辑是如何的?
```sh
# 1/2/3/4 评分含义
  ┌─────────┬────────────┬───────────────────────────┬─────────────────────────────────────────────────┐
  │  评分   │    含义    │         你的状态          │                  对算法的信号                   │
  ├─────────┼────────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ 1 Again │ 完全没印象 │ 看到答案才想起/根本不认识 │ 记忆失败，stability 大幅下降，重新进入 learning │
  ├─────────┼────────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ 2 Hard  │ 勉强想起来 │ 花了很久、不确定          │ 记忆薄弱，stability 小幅增长                    │
  ├─────────┼────────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ 3 Good  │ 想起来了   │ 稍微思考后正确回忆        │ 正常记忆，stability 按期望增长                  │
  ├─────────┼────────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ 4 Easy  │ 秒出答案   │ 不假思索就知道            │ 记忆很牢，stability 大幅增长                    │
  └─────────┴────────────┴───────────────────────────┴─────────────────────────────────────────────────┘

# 当前 stub 实现的调度逻辑

  ━━━━ New card (首次学习) ━━━━
  Again → 1分钟后再看 (进入 learning)
  Hard  → 6分钟后
  Good  → 10分钟后
  Easy  → 直接4天后 (跳过learning阶段)

  ━━━━ Learning/Relearning (短期巩固) ━━━━
  Again → 5分钟后
  Hard  → 10分钟后
  Good  → 明天 (毕业进入 review)
  Easy  → 4天后 (加速毕业)

  ━━━━ Review (长期复习) ━━━━
  Again → 10分钟后 + lapses+1 (遗忘了, stability减半)
  Hard  → 当前间隔 × 1.2
  Good  → 当前间隔 × 2.5
  Easy  → 当前间隔 × 3.5

  举例：单词 "aberrant" 的一生

  Day 1:  New → 按 Good → 10分钟后再来
          Learning → 按 Good → 明天复习 (毕业!)
  Day 2:  Review, interval=1d → 按 Good → 2.5天后
  Day 4:  Review, interval=2d → 按 Good → 5天后
  Day 9:  Review, interval=5d → 按 Good → 12天后
  Day 21: Review, interval=12d → 按 Hard → 14天后 (增长变慢)
  Day 35: Review, interval=14d → 按 Again → 重新learning!
          Relearning → 10分钟后 → 按 Good → 明天复习
          (stability 被砍半, 从头来)
```
```sh
# 举例：单词 "aberrant" 的一生

  Day 1:  New → 按 Good → 10分钟后再来
          Learning → 按 Good → 明天复习 (毕业!)
  Day 2:  Review, interval=1d → 按 Good → 2.5天后
  Day 4:  Review, interval=2d → 按 Good → 5天后
  Day 9:  Review, interval=5d → 按 Good → 12天后
  Day 21: Review, interval=12d → 按 Hard → 14天后 (增长变慢)
  Day 35: Review, interval=14d → 按 Again → 重新learning!
          Relearning → 10分钟后 → 按 Good → 明天复习
          (stability 被砍半, 从头来)
```

上面说的 New card/Learning/Review 对应的是我在 Today 页面上的 3 个按钮吗?
```sh
# 不完全是。Today 的 3 个按钮是你主动选择学什么，而 New/Learning/Review 是卡片自己的状态。

  Today 按钮                    拉出来的卡片状态
  ─────────────────────────────────────────────────
  Start Learning (mixed)   →   Due cards (learning/review/relearning 到期的)
                               + New cards (最多10张)

  Review Due (reviewOnly)  →   只有 Due cards (已学过且到期的)

  New Words (newOnly)      →   只有 New cards (从未见过的, 最多20张)

# 关键区别
  卡片状态是 FSRS 自动管理的生命周期：
  New → Learning → Review ⇄ Relearning
       (你不控制)
```

清楚了, 现在梳理一下 python 相关代码:
- scripts/pyproject.toml 我感觉可以放到项目顶层 -- 我一般习惯用 py, 这里默认激活也没问题 (用于数据处理)?
- 将之前梳理数据用到的 source 移动到 data/ 目录下; 在 @data/README.md 写一下说明



# Notes
[todo]
- ai: 
  - [ ] chatbot sidebar; daily review
- FSRS: 基础实现, 后续待优化
- feat: 
  - [ ] feat: dictionary
  - [ ] feat: 任意单词查询
  - [ ] feat: 用户 mark 功能
  - [x] qwerty-learner 形式的 typing 练习
  - [ ] web 页
- basic
  - [x] 安装到本机 -- 直接 build release
  - [x] vocabulary?
  - [x] keybaord shortcuts
  - [ ] github action
- view
  - [x] stats 页面
- thoughts
  - 只记忆单词的效果有限, 肯定要结合时文/试题阅读 -- 包括 typing (也可以做拼写速度比赛?)
  - AI pet: 陪伴学习

[notes]
- macos 开发工具链
  - [Xcode](https://developer.apple.com/xcode)
  - [sf-symbols](https://developer.apple.com/sf-symbols/): 图标开发
- 开发流程: 
  - 在 Xcode 中新建项目, 从而生成 `Erudite.xcodeproj` 等文件
  - 项目目录结构: erudite/Erudite/Erudite.xcodeproj 的形式; vscode 编辑根目录; Xcode 打开project (`open /Users/frankshi/Projects/app/erudite/Erudite/Erudite.xcodeproj`)
  - swift -> xcode 的好处: 断点调试、Instruments 性能分析、代码签名、网络 entitlement（后续接 AI API）、正确的 .app bundle 分发。
  - build 方案: 区分 debug/release 版本, 后者没有断点调试等功能会小一点
    - `Product → Archive`: '/Users/frankshi/Library/Developer/Xcode/Archives/2026-05-26/Erudite 5-26-26, 19.30.xcarchive'
    - `Product → Build`: /Users/frankshi/Library/Developer/Xcode/DerivedData/Erudite-glnunjjzlfhhqpdgjdcoemndgjow/Build/Products/Release/Erudite.app
- Erudite 项目
  - 工具:
    - GRDB: [github](https://github.com/groue/GRDB.swift) Swift 生态下的 sqlite 工具
    - FSRS (Free Spaced Repetition Scheduler) 模型 [墨墨背单词](https://memodocs.maimemo.com/docs/2022_KDD) 开源的 [group](https://github.com/open-spaced-repetition); [算法说明](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)
  - 词库:
    - [dict](https://github.com/kajweb/dict/) -- 爬取自有道背单词
    - [GRE-CN](https://github.com/LER0ever/GRE-CN) 解析了一些 GRE 书籍
    - [ECDICT](https://github.com/skywind3000/ECDICT) "Free English to Chinese Dictionary Database", 词典很全
    - [Qwerty Learner](https://github.com/RealKai42/qwerty-learner) 22k [web](https://qwerty.kaiyi.cool/); 支持 vscode 插件, 也有在线版
      - 词库包括: GMAT, GRE, IELTS, SAT, TOEFL, CET-4, CET-6. e.g. [gre3000](https://github.com/RealKai42/qwerty-learner/blob/master/public/dicts/GRE3000_3_T.json) 但内容比较简单; 发音方案如何做的?
      - 同义词: [gre-equivalent](https://github.com/RealKai42/qwerty-learner/blob/master/public/dicts/GRE_equivalent.json) 
- 整体 UI 设计
  - 主体交互 (sidebar)
    - Today: 首页
    - Plan: 计划管理
    - Flashcard: 背单词
    - Typing: 打字记忆
    - Library: 词库管理
    - Stats: 统计
  - 组件
    - Popover: 单词速查
    - WordDetail: 单词详情, 操作
- features
  - FSRS: 核心记忆逻辑, @Erudite/Erudite/Engine/FSRS/FSRSEngine.swift
    - ⚠️  当前是 stub，还没实现完整 FSRS-5
  - keybaord shortcuts
  - 自动语音播放
  - 多词书 (workbook)
    - 词义数据: 
    - 词书 (list) 数据源: #qwerty-learner
  - view: stats (dashboard)
- flashcard | FSRS -- 核心 UI 组件可和 typing 共享
  - feat: 核心的翻看单词-标记 again/hard/good/easy 模式
  - feat: 快捷键/键盘操作
  - [ ] 单词排序逻辑?
- typing (对标 qwerty-learner)
  - feat: 循环读音; 切换英音/美音
  - feat: 支持顺序/乱序
  - feat: 实时输入统计: WPM, 输入/正确数
  - feat: 隐藏元音/辅音/全部/部分字符
  - feat: 章节小结
  - feat: 键入错误回退/输入无效
  - feat: 激活/退出 typing 状态
- dictionary
  - feat: 所有单词均可点击查看词义, 可嵌套
  - feat: 加入 "生词本"
- pitfalls
  - 没有提示音: 可能是系统 alert volume 设置为 0!
- feat: 实现 swift 下的 agent 体系
  - Anthropic 服务: types (Messages API), SSE 行协议解析器 (SSEParser), http 层 (SSEParser)
  - 核心 agent 体系: ReAct 实现 (AgentRuntime), SystemPrompt
  - 工具层: AITool (Protocol + ToolRegistry)