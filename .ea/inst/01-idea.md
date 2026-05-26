
# Erudite
## discuss
我在备考 GRE, 想要做一个帮助背单词的 APP, 一步步跟我讨论一下
- GRE 的考试要求是什么? 有哪些官方材料? 官方单词列表有什么?
- 从背单词的角度, 有什么方法论? 应该如何设计一个在 macos 上的辅助 app?
```sh
# 一、GRE 考试现状（2023 年 9 月改版后）

  结构（"短版 GRE"，约 1h58min）：
  - Analytical Writing：1 题（Issue），30 min
  - Verbal Reasoning：2 个 section，27 题，41 min
  - Quantitative Reasoning：2 个 section，27 题，47 min
  - 总分：V 130–170，Q 130–170，AW 0–6
  Verbal 题型（直接和词汇挂钩）：
  - Text Completion (TC)：1–3 空填空，重词义辨析
  - Sentence Equivalence (SE)：找两个能给出同义句的词
  - Reading Comprehension (RC)：长难句 + 学术阅读
  TC 和 SE 几乎是纯词汇 + 逻辑题，词汇量直接决定 V 分数。

# 二、官方材料

  ETS 出品的"真·官方"：
  - The Official Guide to the GRE General Test (OG) — 官方指南
  - PowerPrep Online（免费 2 套）/ PowerPrep Plus（付费 3 套）— 最贴近真实考试
  - Official GRE Verbal Reasoning Practice Questions / Quantitative ... — 官方题集
  - ScoreItNow! — 写作机评

# 方法论
  1. 间隔重复（SRS） — Anki/SuperMemo/FSRS 算法，按遗忘曲线调度复习
  2. 主动回忆（Active Recall） — 测试 > 重读，看到词义反应出单词，或反之
  3. 词根词缀 + 词源 — GRE 词多源于拉丁/希腊，etymology 显著提升记忆效率
  4. 语境记忆 — 真题例句、原版阅读，比孤立词义记得牢
  5. 同反义词组（Word Cluster） — SE 题直接考同义对，按"义群"记效率最高
  6. 多模态 — 音、形、义结合（听音、看拼写、造句）
  7. 错词本 / Leech 管理 — 反复错的词单独高频处理

# ⏺ User answered Claude's questions:
  ⎿  · 你倾向于什么形态的 macOS App？ → 独立窗口 App
     · 技术栈偏好是什么？ → Swift + SwiftUI (原生)
     · 核心功能优先级？哪些是你最想要的？ → 间隔重复引擎 + 学习统计, GRE 语境强化, 词根词缀拆解 + 联想记忆,
     AI 辅助（释义生成/造句/Quiz）
```
```sh
# 依赖库选型
  ┌──────────┬───────────────────────────┬────────────────────────────┐
  │   用途   │          推荐库           │            备注            │
  ├──────────┼───────────────────────────┼────────────────────────────┤
  │ 数据库   │ GRDB.swift                │ SQLite 封装，类型安全      │
  ├──────────┼───────────────────────────┼────────────────────────────┤
  │ 图表     │ Swift Charts (系统内置)   │ macOS 14+，苹果官方        │
  ├──────────┼───────────────────────────┼────────────────────────────┤
  │ 网络     │ URLSession (系统内置)     │ AI API 调用，无需第三方    │
  ├──────────┼───────────────────────────┼────────────────────────────┤
  │ JSON     │ Codable (系统内置)        │ 词库数据解析               │
  ├──────────┼───────────────────────────┼────────────────────────────┤
  │ Markdown │ swift-markdown            │ AI 返回内容渲染            │
  ├──────────┼───────────────────────────┼────────────────────────────┤
  │ 音频     │ AVFoundation (系统内置)   │ 单词发音播放               │
  ├──────────┼───────────────────────────┼────────────────────────────┤
  │ FSRS     │ 自实现 or fork swift-fsrs │ 核心算法，建议理解后自实现 │
  └──────────┴───────────────────────────┴────────────────────────────┘
  设计原则：最小外部依赖，充分利用 Apple 原生框架。
# 架构模式
  MVVM + Repository Pattern
  ┌──────────┐     ┌──────────────┐     ┌─────────────┐
  │   View   │ ←→  │  ViewModel   │ ←→  │  Repository │
  │ (SwiftUI)│     │ (@Observable)│     │  (Protocol) │
  └──────────┘     └──────────────┘     └──────┬──────┘
                                                │
                                ┌────────────────┼────────────────┐
                                │                │                │
                       ┌────────▼───┐   ┌───────▼──────┐  ┌─────▼─────┐
                       │ DatabaseSvc│   │  AIService   │  │ FSRSEngine│
                       │  (GRDB)    │   │  (Claude)    │  │           │
                       └────────────┘   └──────────────┘  └───────────┘

  - @Observable (Swift 5.9+) 替代 ObservableObject，更简洁
  - Repository 层隔离数据访问，方便测试和替换实现
  - Engine 层纯逻辑，无 UI/IO 依赖，100% 可测试
```

技术细节上面可以后续再讨论, 我感觉还是需要从产品功能上先细化:
- 核心定位: 我希望我的 app 是 AI 原生的, 满足我的需求的一个 app
    - 有一个 "后台老师", 我在界面任何时候都可以随时提问; 最好能 context-aware, 它知道我在什么地方可能的疑问是什么
    - 持续进化的, 它能总结我每天的学习进展, 定制化的生成后续的学习计划 -- 更有针对性;
    - 结合不同的形式来帮我背词, e.g. 词根分析; 联想记忆等
- 功能维度, 需要构想一下交互形式会有哪些?
    1. FSRS 形式的背单词, 上面讨论过的类似 Anki/其他背单词 app 的形式 -- 这块可能需要明确一下词库数据来源
    2. "复习" 页面: 参考我试用的 GRE3000词 app, 它提供了 flashcard (抽认卡复习, 推荐前中期使用); 做题巩固 (根据词选中义/根据英文意思选词两种模式); 极速刷词 (自动语音过一遍, 推荐后期熟练后使用) -- 想一下哪些形式是合理的?
    3. 其他: 上面讨论的 AI 能力如何融合?
    4. (后续, 暂不考虑) 背词熟悉后, 后期结合 GRE 真题做练习?
```sh
# 主动 vs 被动
  被动模式 (用户触发):
    - 点击任何单词 → 随时提问
    - 输入自然语言问题 → 得到基于当前上下文的回答
    - "帮我比较 X 和 Y"
    - "用中文给我讲个故事记住这个词"

  主动模式 (AI 触发, 需要克制):
    - 检测到困难模式 → 底部浮现提示气泡 (不打断)
    - 每日开始时 → 简短 briefing (今天计划)
    - 每日结束时 → 学习总结 + 明日建议
    - 检测到常见混淆对 → 提供辨析 (可关闭)

# 学习模式
模式总览 & 适用阶段

  学习阶段:    [初见] ——→ [初记] ——→ [巩固] ——→ [熟练] ——→ [应用]
                │          │          │          │          │
  适用模式:    学习卡片    抽认卡     做题巩固    极速刷词    真题练习
               + AI讲解   + 词根联想   + SE/TC    + 听力复习   (后续)
```
帮我想一下这个 app 应该叫什么名字? 有什么推荐?
// erudite
确定叫 erudite! 汇总上面的讨论, 整理成 spec 文件到 @/Users/frankshi/Projects/app/erudite/.ea/spec/ 目录下

@/Users/frankshi/Projects/.ea-index/.claude-plugin/skills/forge-create/SKILL.md 搭建项目骨架
- Xcode project /纯 Swift Package 的差异是什么?
- FSRS 引擎骨架有什么用?
可以, 创建 issue 并实现
```sh
# Xcode Project vs 纯 Swift Package
  ┌──────────────┬────────────────────────────────┬─────────────────────────────┐
  │              │   Xcode Project (.xcodeproj)   │      纯 Swift Package       │
  │              │                                │       (Package.swift)       │
  ├──────────────┼────────────────────────────────┼─────────────────────────────┤
  │ 适合         │ 完整 macOS                     │ 库 / CLI 工具 / 服务端      │
  │              │ App（有窗口、菜单栏、沙盒）    │                             │
  ├──────────────┼────────────────────────────────┼─────────────────────────────┤
  │ Bundle       │ ✅ 自动生成 .app bundle        │ ❌ 需要额外配置才能打包     │
  ├──────────────┼────────────────────────────────┼─────────────────────────────┤
  │ 资源文件     │ Assets.xcassets、words.json    │ 需要声明 resources in       │
  │              │ 直接拖入                       │ Package.swift               │
  ├──────────────┼────────────────────────────────┼─────────────────────────────┤
  │ Entitlements │ ✅ 沙盒、网络权限、文件访问    │ ❌ 不支持                   │
  ├──────────────┼────────────────────────────────┼─────────────────────────────┤
  │ App 生命周期 │ @main struct EruditeApp: App   │ 可以但不自然                │
  │              │ {} 原生支持                    │                             │
  ├──────────────┼────────────────────────────────┼─────────────────────────────┤
  │ 签名/分发    │ ✅ Xcode                       │ 需要手动 xcodebuild         │
  │              │ 管理签名、notarization         │                             │
  ├──────────────┼────────────────────────────────┼─────────────────────────────┤
  │ 依赖管理     │ 内嵌 SPM（File → Add Package） │ 原生 SPM                    │
  ├──────────────┼────────────────────────────────┼─────────────────────────────┤
  │ CI/CD        │ xcodebuild                     │ swift build（但 macOS app   │
  │              │                                │ 还是要 xcodebuild）         │
  └──────────────┴────────────────────────────────┴─────────────────────────────┘
```
配置 gitignore


## debug -> Xcode project
跑到下面不动了, 好像没有弹出来一个 app?
```sh
➜ swift run
[1/1] Planning build
Building for debugging...
[195/195] Applying Erudite
Build of product 'Erudite' complete! (35.42s)
```
运行 `swift run` 和在 Xcode 中点击 run 图标有什么差异?
```sh
  ┌──────────┬────────────────────┬───────────────────────────────────┐
  │          │     swift run      │          Xcode Run (▶️ )           │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ 本质     │ 直接执行编译出的二 │ 打包成 .app bundle 后启动         │
  │          │ 进制文件           │                                   │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ 产物路径 │ .build/debug/Erudi │ DerivedData/.../Erudite.app/Conte │
  │          │ te (裸二进制)      │ nts/MacOS/Erudite                 │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ App      │ ❌ 没有            │ ✅ 完整 .app 结构 (Info.plist,    │
  │ Bundle   │                    │ 签名, entitlements)               │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │          │ 后台进程（需手动   │                                   │
  │ 进程身份 │ setActivationPolic │ 正经前台 GUI 应用                 │
  │          │ y）                │                                   │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ Dock     │ 默认没有           │ ✅ 有                             │
  │ 图标     │                    │                                   │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ 菜单栏   │ 默认不显示 app     │ ✅ 正常显示                       │
  │          │ 菜单               │                                   │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ 代码签名 │ ❌ 未签名          │ ✅ Xcode 自动签名                 │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ Entitlem │ ❌ 无（网络、沙盒  │ ✅ 按配置生效                     │
  │ ents     │ 等权限不生效）     │                                   │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ 资源加载 │ Bundle.module（SPM │ Bundle.main（app bundle 内）      │
  │          │  resource bundle） │                                   │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ 调试器   │ 无（除非手动       │ ✅ 自动                           │
  │          │ attach lldb）      │ attach，断点/内存分析全可用       │
  ├──────────┼────────────────────┼───────────────────────────────────┤
  │ 环境变量 │ 继承终端 shell     │ Xcode scheme 中配置               │
  └──────────┴────────────────────┴───────────────────────────────────┘
```
- 规范开发流程: 后续统一走 Xcode 来编译 app 出来. 这样的话, 还有必要保留 Package.swift 吗?
- 修复 Xcode 报错: (只是 warning!)
```sh
Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}
Error registering app with intents framework: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}
Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}
Unable to re-register with Process Instance Registry, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}
Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}
Unable to re-register with Process Instance Registry, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}
Will NOT re-try to establish the connection
Unable to get synchronousRemoteObjectProxy, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}
Unable to re-register with Process Instance Registry, error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.linkd.autoShortcut" UserInfo={NSDebugDescription=connection to service named com.apple.linkd.autoShortcut}
Cannot index window tabs due to missing main bundle identifier
Unable to obtain a task name port right for pid 401: (os/kern) failure (0x5)
```
```sh
# 结论：保留 Package.swift，但主力开发用 Xcode 项目。
  ┌───────────────────────────────┬─────────────────────┬────────────────┐
  │             用途              │    Package.swift    │   .xcodeproj   │
  ├───────────────────────────────┼─────────────────────┼────────────────┤
  │ 日常开发/Run                  │         ❌          │       ✅       │
  ├───────────────────────────────┼─────────────────────┼────────────────┤
  │ Info.plist / Bundle ID        │      ❌ 不支持      │       ✅       │
  ├───────────────────────────────┼─────────────────────┼────────────────┤
  │ Entitlements (网络/沙盒)      │         ❌          │       ✅       │
  ├───────────────────────────────┼─────────────────────┼────────────────┤
  │ App 签名/分发                 │         ❌          │       ✅       │
  ├───────────────────────────────┼─────────────────────┼────────────────┤
  │ CI 快速编译检查 (swift build) │         ✅          │ 需要 Xcode CLI │
  ├───────────────────────────────┼─────────────────────┼────────────────┤
  │ 命令行跑测试 (swift test)     │         ✅          │   也行但更重   │
  ├───────────────────────────────┼─────────────────────┼────────────────┤
  │ 定义 SPM 依赖                 │ ✅ (Xcode 自动识别) │   引用同一份   │
  └───────────────────────────────┴─────────────────────┴────────────────┘

# 正确做法：创建 Xcode 项目
  当前我们的 SPM 方式可以编译运行，但缺少正式 macOS app 需要的：
  - Info.plist（Bundle ID、版本号、权限声明）
  - Entitlements（网络访问权限 — 后续接 AI API 必须）
  - 代码签名
  - App 图标

  在 Xcode 中操作：

  1. File → New → Project
  2. 选 macOS → App
  3. 配置:
     - Product Name: Erudite
     - Organization Identifier: com.yourname (如 com.frankshi)
     - Interface: SwiftUI
     - Language: Swift
     - 保存到 /Users/frankshi/Projects/app/erudite/ (覆盖)
  4. 删除 Xcode 自动生成的 ContentView.swift 等模板文件
  5. 把 Sources/Erudite/ 下的文件拖入项目
  6. File → Add Package Dependencies → 添加 GRDB.swift
```
我创建之后放到了 /Users/frankshi/Projects/app/erudite/Erudite/ 中, 帮调整一下

总结一下:
- 我们将项目从 swift 项目转为 Xcode 项目 (通过 Xcode.app 创建), 从而引入了 Xcode 的一些特性 (有利于后期开发)
- 将原本的代码都迁移到了 Erudite/Erudite/ 目录下
  - 这样在 erudite/ 根目录下创建一个子目录 (一个 Xcode 项目的开发模式常见吗? 大小写命名规范?)
  - 之前的 Tests/ Package.swift 为什么都不需要了?
```sh
# 迁移了什么
  ┌───────────────────────────┬──────────────────────────────────────────────────────────┐
  │      之前 (SPM 项目)      │                    现在 (Xcode 项目)                     │
  ├───────────────────────────┼──────────────────────────────────────────────────────────┤
  │ Package.swift 定义项目    │ Erudite.xcodeproj 定义项目                               │
  ├───────────────────────────┼──────────────────────────────────────────────────────────┤
  │ Sources/Erudite/ 放代码   │ Erudite/Erudite/ 放代码                                  │
  ├───────────────────────────┼──────────────────────────────────────────────────────────┤
  │ swift build / swift run   │ Xcode ▶️  Run                                             │
  ├───────────────────────────┼──────────────────────────────────────────────────────────┤
  │ 无 Info.plist / Bundle ID │ ✅ 自动生成 Info.plist, Bundle ID = site.easonsi.Erudite │
  ├───────────────────────────┼──────────────────────────────────────────────────────────┤
  │ 无签名 / 无 entitlements  │ ✅ 自动签名 + App Sandbox                                │
  ├───────────────────────────┼──────────────────────────────────────────────────────────┤
  │ Bundle.module 加载资源    │ Bundle.main 加载资源                                     │
  └───────────────────────────┴──────────────────────────────────────────────────────────┘
  Xcode 项目带来的好处：断点调试、Instruments 性能分析、代码签名、网络 entitlement（后续接 AI
  API）、正确的 .app bundle 分发。
```
```sh
# Xcode 项目的标准结构：
  myproject/              ← git 仓库根目录 (小写, kebab-case 或 lowercase)
  ├── .git/
  ├── .gitignore
  ├── README.md
  ├── MyApp/              ← Xcode 项目目录 (PascalCase, 与产品名一致)
  │   ├── MyApp.xcodeproj
  │   └── MyApp/          ← 源码目录 (与 target 名一致)
  │       └── ...
  └── MyAppTests/         ← 测试 target (可选)
```
这种项目结构的话, 我在 vscode 中可以打开根目录; 那么在 Xcode 中应该打开 .xcodeproj 还是 根目录?
// open /Users/frankshi/Projects/app/erudite/Erudite/Erudite.xcodeproj

## spec
将上面的讨论 (开发规范) 整理到 spec 中; 另外迁移到 Xcode 应该也可以形成一个 issue

生成项目 CLAUDE.md 文件, 概述项目基本目标 & 目录结构, 引用关键的 spec 文件

## discuss branch 2
产品方向: 我希望是 AI 原生的 -- 在背单词过程中我可以随时提问; AI 每天总结我的内容; 构建词根解析等能力
技术架构: 倾向于采用 macos 原生
```sh
# 具体可落地的 AI 能力：
  ┌────────────┬──────────────────────────────────────────────────────────────────────┬───────────────────┐
  │    能力    │                                 形态                                 │      触发点       │
  ├────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────┤
  │ 对话式复习 │ 不只 flip card，AI 可以让你"在某语境下用这个词造句"，再点评          │ 每张卡片旁的 Chat │
  ├────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────┤
  │ 即时提问   │ "为什么 obsequious 和 sycophantic 都翻译成谄媚？" → AI 给辨析 + 例句 │ 任意词面板        │
  ├────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────┤
  │ 词根树     │ 输入 "spect" 自动展开 inspect / aspect / prospect / circumspect...   │ 词条详情页        │
  ├────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────┤
  │ 个性化例句 │ 知道你的兴趣（ML、考研）→ 例句围绕你熟悉的语境                       │ 卡片背面          │
  ├────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────┤
  │ 错因分析   │ "你这周在'否定前缀'词上错得多（dis-/un-/in-）" → 给针对性卡组        │ 每日复盘          │
  ├────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────┤
  │ AI 日记    │ 今天学了什么、薄弱点、明日 plan                                      │ 每日定时生成      │
  ├────────────┼──────────────────────────────────────────────────────────────────────┼───────────────────┤
  │ 真题反查   │ 输入生词 → 找到它在哪套真题/哪篇 RC 里出现                           │ 词条详情          │
  └────────────┴──────────────────────────────────────────────────────────────────────┴───────────────────┘
```
1. 交互范式: C 双栏并列
2. 词表: 合理的, 应该内置已有词表+支持外部导入
下面讨论具体的 UI 交互设计

## macos dev workflow
先来帮我配置 macos 原生开发所需要的工具? 我之前主要用 vscode+cli 工具, 有什么需要新安装的吗
```sh
# 一、必装（Required）
  1. Xcode
  - 这是绕不开的——Swift 编译器、SwiftUI Previews（实时预览画布）、模拟器、签名、上架都依赖它
  - 来源：Mac App Store（免费，但下载 ~15GB，安装后占盘 ~40GB）
  - 第一次启动会让你接受许可、再装一堆组件，预留 30 分钟+

  2. Xcode Command Line Tools
  - 装完 Xcode 一般自带；保险起见：
  xcode-select --install
  - 验证：xcodebuild -version 和 swift --version 都能输出

  3. Apple ID（免费开发者账号）
  - 用现有 Apple ID 登录 Xcode 即可，不需要 $99 的付费 Developer Program
  - 付费账号在以下情况才需要：上架 Mac App Store / TestFlight / 用 iCloud 等高级 capability
  - MVP 阶段：免费账号完全够，本地 Run/Debug 不受限
```

我安装好 Xcode 了, 先来给我普及一下, macos app 的开发流程是怎样的?
```sh
# 心智模型对照
  ┌───────────────┬────────────────────────────────────────┬──────────────────────────────────┐
  │ Web/Node 概念 │            Xcode/Swift 对应            │               区别               │
  ├───────────────┼────────────────────────────────────────┼──────────────────────────────────┤
  │ package.json  │ .xcodeproj / .xcworkspace              │ 二进制可编辑文件，不是 JSON      │
  ├───────────────┼────────────────────────────────────────┼──────────────────────────────────┤
  │ src/          │ App target 下的文件夹                  │ 物理目录和 Xcode                 │
  │               │                                        │ 里看到的"虚拟分组"可以不一致     │
  ├───────────────┼────────────────────────────────────────┼──────────────────────────────────┤
  │ npm install   │ Swift Package Manager（在 Xcode 里加） │ 锁文件叫 Package.resolved        │
  ├───────────────┼────────────────────────────────────────┼──────────────────────────────────┤
  │ npm run dev   │ 选 Scheme → ⌘R（Run）                  │ 没有 watch 模式，但有 SwiftUI    │
  │               │                                        │ Preview（更强）                  │
  ├───────────────┼────────────────────────────────────────┼──────────────────────────────────┤
  │ webpack/vite  │ xcodebuild                             │ 一般你不直接调用，Xcode 帮你跑   │
  ├───────────────┼────────────────────────────────────────┼──────────────────────────────────┤
  │ node_modules/ │ ~/Library/Developer/Xcode/DerivedData/ │ 编译缓存放用户目录，不进项目     │
  ├───────────────┼────────────────────────────────────────┼──────────────────────────────────┤
  │ dist/         │ .app bundle（其实是个文件夹）          │ 双击就能运行                     │
  └───────────────┴────────────────────────────────────────┴──────────────────────────────────┘
  
  关键概念四件套（Xcode 黑话，不懂会一脸懵）：
  
  - Workspace：可以包含多个 Project（多模块场景）。我们暂时不需要。
  - Project：.xcodeproj，一个产品的所有源码+配置
  - Target：一个具体的构建产物（App、Test、Widget 各一个 target）
  - Scheme：一组"如何构建/运行/测试"的配置（Debug 用哪个 target、传哪些参数）

  → 你绝大多数时间面对的是 一个 Project，一个 App Target，一两个 Scheme。

# 项目结构（新建 SwiftUI macOS App 之后）
  Radix/                          ← 仓库根目录
  ├── Radix.xcodeproj/            ← Xcode 项目配置（二进制 plist）
  ├── Radix/                      ← 源码目录
  │   ├── RadixApp.swift          ← 入口（@main，相当于 main.ts）
  │   ├── ContentView.swift       ← 第一个 View
  │   ├── Assets.xcassets/        ← 图标 / 颜色 / 图片
  │   │   ├── AppIcon.appiconset
  │   │   └── AccentColor.colorset
  │   ├── Info.plist              ← App 元信息（可能内联在 project，看版本）
  │   └── Radix.entitlements      ← 权限声明（沙盒/网络/文件访问）
  ├── RadixTests/                 ← 单元测试 target
  └── RadixUITests/               ← UI 测试 target

  重点理解：
  - RadixApp.swift 里的 @main 是 Swift 5.3+ 的特性，等价于"程序入口"
  - Assets.xcassets 是个"伪文件夹"——双击在 Xcode 里编辑，不要手动改里面的 JSON
  - .entitlements 决定你 App 能干什么（联网？读硬盘？用 iCloud？）——沙盒环境下这非常重要

# 调试
  ┌──────────────┬───────────────────────────────────────┬───────────────────────────────────┐
  │     工具     │                 用途                  │               类比                │
  ├──────────────┼───────────────────────────────────────┼───────────────────────────────────┤
  │ Breakpoint   │ 点行号左侧加断点                      │ 同 VSCode                         │
  ├──────────────┼───────────────────────────────────────┼───────────────────────────────────┤
  │ LLDB         │ 底层调试器，Console 里输入 po obj     │ 类似 gdb                          │
  │              │ 打印对象                              │                                   │
  ├──────────────┼───────────────────────────────────────┼───────────────────────────────────┤
  │ View         │ ⌘ 暂停 → Debug View Hierarchy，3D     │ 类似浏览器 DevTools 的 Elements   │
  │ Debugger     │ 拆解 UI                               │                                   │
  ├──────────────┼───────────────────────────────────────┼───────────────────────────────────┤
  │ Instruments  │ 性能/内存/泄漏分析                    │ 类似 Chrome DevTools 的           │
  │              │                                       │ Performance tab                   │
  ├──────────────┼───────────────────────────────────────┼───────────────────────────────────┤
  │ print()      │ 永远的好朋友                          │ console.log                       │
  └──────────────┴───────────────────────────────────────┴───────────────────────────────────┘

# Apple 特有的概念（绕不开的几个）

  1. Bundle Identifier

  每个 App 的全球唯一 ID，反向域名风格：com.shieason.radix 这个一旦定下来，未来上架/iCloud/Keychain 同步都基于它，改起来代价大——开项目时就要想清楚。

  2. App Sandbox（沙盒）

  - macOS App 默认启用沙盒——你的 App 不能随便读硬盘、不能默认联网
  - 在 Radix.entitlements 里勾选需要的能力：
    - com.apple.security.network.client → 联网（调 Claude API 要这个）
    - com.apple.security.files.user-selected.read-write → 用户主动选的文件
    - com.apple.security.app-sandbox → 沙盒本身
  - 不开沙盒也行（开发期），但要上 Mac App Store 必须开

  3. Info.plist

  App 的元信息（版本号、最低系统要求、必要权限的弹窗文案等）。新版 Xcode 把它内联到了 Project 设置里，不一定看到独立文件。

  4. Code Signing
  
  所有 macOS App 都必须签名才能运行：
  - 本地开发：Xcode 自动用你的 Apple ID 签个临时证书（免费），机器换了要重新签
  - 分发给别人：需要付费 Developer Program（$99/年）拿 Developer ID 证书
  - 不签名直接运行 → Gatekeeper 拦你 "无法验证开发者"
```
```sh
# 一张图总结

     编写代码 ───→ SwiftUI Preview ───→ Build & Run ───→ 调试
     (VSCode/Xcode)   (Xcode 必备)        (⌘R)            (LLDB/View Debugger)
                                            ↓
                                         本地运行的 .app
                                            ↓
                                      (未来) Archive → 公证 → 分发

  整个流程里 Apple 平台最特别的三件事：
  1. SwiftUI Preview ——开发体验远超 web HMR，记得用
  2. Code Signing ——所有 App 必须签名，免费账号本地够用
  3. Sandbox + Entitlements ——能力要在 .entitlements 里显式声明，否则代码运行时静默失败
```


# Notes
- macos 开发工具链
  - [Xcode](https://developer.apple.com/xcode)
  - [sf-symbols](https://developer.apple.com/sf-symbols/): 图标开发
- 开发流程: 
  - 在 Xcode 中新建项目, 从而生成 `Erudite.xcodeproj` 等文件
  - 项目目录结构: erudite/Erudite/Erudite.xcodeproj 的形式; vscode 编辑根目录; Xcode 打开project (`open /Users/frankshi/Projects/app/erudite/Erudite/Erudite.xcodeproj`)
  - swift -> xcode 的好处: 断点调试、Instruments 性能分析、代码签名、网络 entitlement（后续接 AI API）、正确的 .app bundle 分发。
- Erudite 项目
  - 工具:
    - GRDB: [github](https://github.com/groue/GRDB.swift) Swift 生态下的 sqlite 工具
    - FSRS (Free Spaced Repetition Scheduler) 模型 [墨墨背单词](https://memodocs.maimemo.com/docs/2022_KDD) 开源的 [group](https://github.com/open-spaced-repetition); [算法说明](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)
  - 词库:
    - [dict](https://github.com/kajweb/dict/) -- 爬取自有道背单词
    - [ECDICT](https://github.com/skywind3000/ECDICT) "Free English to Chinese Dictionary Database", 词典很全
    - [Qwerty Learner](https://github.com/RealKai42/qwerty-learner) 22k [web](https://qwerty.kaiyi.cool/); 支持 vscode 插件, 也有在线版
      - 词库包括: GMAT, GRE, IELTS, SAT, TOEFL, CET-4, CET-6. e.g. [gre3000](https://github.com/RealKai42/qwerty-learner/blob/master/public/dicts/GRE3000_3_T.json) 但内容比较简单; 发音方案如何做的?
      - 同义词: [gre-equivalent](https://github.com/RealKai42/qwerty-learner/blob/master/public/dicts/GRE_equivalent.json) 
