
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

## vocabulary
总结本项目的进展, 考虑后续规划.
我感觉我们把基本项目框架搭好了, 下一步最关键的是把最核心的词库构建起来?

先帮我调研一下, 有哪些好用的词库?
- 就 GRE 方向, 我最近试了 "GRE3000词" 手机app, 内置了 GRE 高频 3000 词 (2026 版) / 考满分 GRE 全能 6000 词; 其分 list/unit 来划分词库, 一个单元一个单元背感觉更有 "打卡" 的进度感
```sh
  ┌──────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────┐
  │               资源               │                                      价值                                      │
  ├──────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ RealKai42/qwerty-learner (15k⭐) │ 有 GRE_equivalent.json — SE 等价词配对数据，对我们的 SE 练习模式很关键         │
  ├──────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ skywind3000/ECDICT (12k⭐)       │ 76万词条，含 BNC/COCA 词频数据，可以用更科学的频率排序替代我们目前的交叉验证法 │
  ├──────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ 张巍 等价词                      │ ~900 同义词组，专为 GRE Sentence Equivalence 设计                              │
  └──────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────┘
```

subagent 为什么跑了这么久? 可以加速吗? (开发效率很重要)

我下载了 /Users/frankshi/Downloads/GRE_2.json | GRE_3.json; 另外从另一个 repo 下载了一些词库:
- /Users/frankshi/Downloads/GRE-CN-master/L-GRE-词汇/L-GRE-再要你命3000/L-GRE-再要你命3000顺序版/L-GRE-再要你命3000.csv
- /Users/frankshi/Downloads/GRE-CN-master/L-GRE-词汇/L-GRE-佛脚词汇/L-GRE-佛脚词汇/L-GRE-佛脚词表.csv
- /Users/frankshi/Downloads/GRE-CN-master/L-GRE-词汇/L-GRE-Magoosh/L-GRE-MagooshFlashcard.csv
帮我分析一下那个比较好?
处理脚本写到 scripts/ 目录下, 使用 uv add 管理 python 环境
```sh
  词库已经构建好了 ✅：
  - scripts/build_worddb.py — 一键重建
  - words.json — 6515 词，66 Lists，字段覆盖率 90%+
  - 运行: cd scripts && uv run build_worddb.py
```

先把这个词库加到 erudite 中吧, 我先测试一下 app

可以看到词表了!
参考 @/Users/frankshi/Projects/.ea-index/.claude-plugin/skills/forge-create/SKILL.md 是不是可以生成一个 done issue?

想一下后续还有哪些事项? 我希望能把整个 app run 起来, 我一边测试一边优化
创建相应的 issues, 然后开始实现

## basic qa
基本可用了! 我们快问快答:
- 首先, 目前的 words schema 是什么? 包含哪些好用/帮助记忆的模块?
```sh
# Word Shema 一览
  Word
  ├── id / spelling / phonetic          ← 基础标识
  ├── frequency (1=core, 2=common, 3=advanced)  ← 分级
  ├── listIndex / unitIndex             ← 打卡结构 (L1U1 ~ L66U10)
  │
  ├── definitions[]                     ← 🟢 释义 (100%)
  │   ├── partOfSpeech ("v", "adj", "n"...)
  │   ├── chinese ("排挤，取代")
  │   └── english ("to take the place of...")
  │
  ├── examples[]                        ← 🟢 例句 (90%)
  │   ├── sentence
  │   └── source ("dictionary" | "magoosh")
  │
  ├── synonymGroups[[]]                 ← 🟢 同义词组 (91%) — SE配对练习用
  │
  ├── mnemonics[]                       ← 🟡 助记 (65%)
  │   └── "sup(下面) + plant(种植) → 排挤"
  │
  ├── roots: MorphemeBreakdown?         ← 🔴 词根拆解 (0% — 待AI补全)
  │   ├── segments[{text, type, meaning}]
  │   └── logic
  │
  ├── antonyms[]                        ← 🔴 反义词 (0% — 待补全)
  ├── sentiment                         ← 🔴 情感极性 (全标neutral — 待AI分类)
  └── tags[]                            ← 空，预留用户自定义

# 帮助记忆的模块
  ┌──────────────────────────┬────────┬────────────────────────────────────────────────┐
  │           模块           │ 覆盖率 │                    记忆价值                    │
  ├──────────────────────────┼────────┼────────────────────────────────────────────────┤
  │ mnemonics (助记)         │ 65%    │ ⭐⭐⭐ 词根联想拆解，如 "sup(下面)+plant→排挤" │
  ├──────────────────────────┼────────┼────────────────────────────────────────────────┤
  │ synonymGroups (同义词组) │ 91%    │ ⭐⭐⭐ GRE SE 六选二核心                       │
  ├──────────────────────────┼────────┼────────────────────────────────────────────────┤
  │ examples (例句)          │ 90%    │ ⭐⭐ 语境记忆，含 Magoosh GRE 语境例句         │
  ├──────────────────────────┼────────┼────────────────────────────────────────────────┤
  │ definitions (中英双解)   │ 100%   │ ⭐⭐ 中文快速理解 + 英文精确义                 │
  ├──────────────────────────┼────────┼────────────────────────────────────────────────┤
  │ roots (词根拆解)         │ 0%     │ ⭐⭐⭐ 缺失最大的一块 — 系统性构词逻辑         │
  └──────────────────────────┴────────┴────────────────────────────────────────────────┘
```

目前的数据库结构如何? 存放在哪里? (我不太了解 swift 机制)
```sh
# 数据库机制
  ┌─────────────────────────────────────────────────────────────┐
  │  App Bundle (只读，随 app 安装)                               │
  │  ~/Library/Developer/.../Erudite.app/Contents/Resources/    │
  │    └── words.json (5.6MB, 6515词 — 源数据)                  │
  └────────────────────────────┬────────────────────────────────┘
                               │ 首次启动时 seed
                               ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  App Sandbox (读写，用户数据持久化)                            │
  │  ~/Library/Containers/site.easonsi.Erudite/                 │
  │    Data/Library/Application Support/Erudite/                │
  │      └── erudite.db (SQLite — GRDB管理)                     │
  └─────────────────────────────────────────────────────────────┘
# 表结构
  ┌───────────────┬──────┬──────────────────────────────────────────────────────────────┐
  │      表       │ 行数 │                             作用                             │
  ├───────────────┼──────┼──────────────────────────────────────────────────────────────┤
  │ word          │ 6515 │ 词条内容（data 列存完整 JSON blob）                          │
  ├───────────────┼──────┼──────────────────────────────────────────────────────────────┤
  │ reviewCard    │ 6515 │ 每词一张 FSRS 卡片（stability, difficulty, due date, state） │
  ├───────────────┼──────┼──────────────────────────────────────────────────────────────┤
  │ reviewLog     │ 4    │ 每次评分记录（你刚测试产生的）                               │
  ├───────────────┼──────┼──────────────────────────────────────────────────────────────┤
  │ wordList      │ 0    │ 自定义词表分组（预留）                                       │
  ├───────────────┼──────┼──────────────────────────────────────────────────────────────┤
  │ wordListEntry │ 0    │ 词表↔词条多对多关联                                          │
  ├───────────────┼──────┼──────────────────────────────────────────────────────────────┤
  │ studySession  │ 0    │ 学习会话统计（预留）                                         │
  ├───────────────┼──────┼──────────────────────────────────────────────────────────────┤
  │ aiCache       │ 0    │ AI 生成内容缓存（预留）                                      │
  └───────────────┴──────┴──────────────────────────────────────────────────────────────┘
# 关键点：
  - word.data 存的是完整 Word struct 的 JSON — 增删字段不需要改表结构
  - macOS app 默认沙箱化，数据在 ~/Library/Containers/site.easonsi.Erudite/ 下
  - 删 app 会清空沙箱（重装等于重置）
  - 你可以直接用 sqlite3 查询/调试那个 db 文件 
```

如何演化词库?
- 一方面, 预处理得到某一版本的词表; 但一些字段可能是缺失的;
- 在使用 app 的过程中, AI 可能会填补一些字段, 这些字段可以用来优化词表数据吗?
```sh
// 基本方案: 版本号 + 可回流更新词库
# 字段分类
  ┌─────────────────────────────────┬───────────────────────┬────────────────┐
  │              字段               │         来源          │     可变性     │
  ├─────────────────────────────────┼───────────────────────┼────────────────┤
  │ spelling, phonetic, definitions │ 预构建（固定）        │ 基本不变       │
  ├─────────────────────────────────┼───────────────────────┼────────────────┤
  │ frequency, listIndex            │ 预构建（可调）        │ 改版时可能重排 │
  ├─────────────────────────────────┼───────────────────────┼────────────────┤
  │ roots                           │ 🤖 AI batch / runtime │ 补全后固化     │
  ├─────────────────────────────────┼───────────────────────┼────────────────┤
  │ mnemonics                       │ 🤖 AI + 👤 用户自定义 │ 累加，不覆盖   │
  ├─────────────────────────────────┼───────────────────────┼────────────────┤
  │ antonyms, sentiment             │ 🤖 AI batch           │ 补全后固化     │
  ├─────────────────────────────────┼───────────────────────┼────────────────┤
  │ synonymGroups                   │ 预构建 + AI 扩展      │ 可增不删       │
  └─────────────────────────────────┴───────────────────────┴────────────────┘
```

## voice & keyboard shortcuts
生成一个 issue 留待后续优化 (不是特别紧急); 下面想两个更重要的:
- 我希望在学习一个单词的时候, 默认就可以听到发音, 辅助记忆,
    - 这一块, 我感觉可以参考 qwerty-learner? 看看它的数据源是什么? 我 clone 到了 /Users/frankshi/Projects/_inbox/repo/RealKai42/qwerty-learner 你可以参看
- 有什么快捷键体系? 
    - 我希望在学习过程中, 纯键盘操作, 更流畅一些;
    - 快捷键系统有什么方法论吗?
```sh
# macOS app 的选项：
  ┌────────────────────────────────┬────────┬────────┬─────────┬───────────────────┐
  │              方案              │  质量  │  延迟  │  离线   │    实现复杂度     │
  ├────────────────────────────────┼────────┼────────┼─────────┼───────────────────┤
  │ AVSpeechSynthesizer (系统 TTS) │ ⭐⭐   │ 0ms    │ ✅      │ 极简 (3行代码)    │
  ├────────────────────────────────┼────────┼────────┼─────────┼───────────────────┤
  │ 有道 API (同 qwerty-learner)   │ ⭐⭐⭐ │ ~200ms │ ❌      │ 简单 (URLSession) │
  ├────────────────────────────────┼────────┼────────┼─────────┼───────────────────┤
  │ 组合: 有道优先 + TTS 兜底      │ ⭐⭐⭐ │ ~200ms │ ✅ 兜底 │ 中等              │
  └────────────────────────────────┴────────┴────────┴─────────┴───────────────────┘
```
```sh
# 快捷键体系

  方法论：Vim-like 分层 + 渐进披露

  原则:
  1. 最高频操作 → 单键 (不需要修饰符)
  2. 左手主区 → 动作键 (不用移手)
  3. 空格 = 核心确认键 (最大的键, 最快按到)
  4. 数字 = 分级选择 (自然映射)
  5. 不跟系统快捷键冲突

  学习模式快捷键设计

  ━━━━ 卡片学习流程 ━━━━

  Space       → 翻转/显示答案 (核心操作)
  1 / j       → Again (再来)
  2 / k       → Hard  (困难)
  3 / l       → Good  (记住了)
  4 / ;       → Easy  (太简单)

  ━━━━ 导航 ━━━━

  → / n       → 跳过当前卡 (不评分)
  ← / p       → 回看上一张 (只看, 不改评分)
  Esc / q     → 结束本次学习

  ━━━━ 辅助 ━━━━

  r           → 重播发音
  e           → 展开/收起例句
  m           → 显示助记
  s           → 显示同义词
  Tab         → 切换 中文释义 / 英文释义
```

开始实现!
// ~/.claude-internal/plans/hashed-snuggling-scroll.md

快捷键优化:
1. 我在 Today 按 "Start Learning" 之后, 需要到 Learn 页面点击单词卡片才激活快捷键模式, 需要额外一步鼠标操作;
2. Space → 翻转/显示答案, 目前重复按好像无法 toggle
3. 前后导航
  → / n       → 跳过当前卡 (不评分)
  ← / p       → 回看上一张 (只看, 不改评分)

整理上面的实现为 issue


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
## new vocabulary
下一步, 参考 qwerty-learner 的设计, 我希望能够实现多单词本学习的功能 -- e.g. GRE, TOEFL, SAT (况且同一个考试也可以选不同的词书/顺序)
- 一方面是数据, 有哪本词书是词以类记, 难度相对小一点的? 需要构造一下
- 另一方面是 app 架构上, 如何划分不同的学习计划?
    - 后续的 AI 体系中, 哪些做隔离哪些应该共享?
```sh
# "词以类记"数据: qwerty-learner 里有现成的：
┌───────────────────────────────────────────────────┬──────┬────────────────────────────────────────────────────┬───────┐
│                       文件                        │ 词量 │                        特点                        │ 难度  │
├───────────────────────────────────────────────────┼──────┼────────────────────────────────────────────────────┼───────┤
│ gre-ciyileiji.json                                │ 8785 │ 按语义主题排序（地理→气象→生物→…），无显式分类标签 │ 高    │
├───────────────────────────────────────────────────┼──────┼────────────────────────────────────────────────────┼───────┤
│ Categorized_TOEFL_Vocabulary_by_Zhanghongyan.json │ 4123 │ 有编号分类(1.1, 1.2...) + 词根助记，张红岩         │ ⭐    │
│                                                   │      │                                                    │ 中等  │
├───────────────────────────────────────────────────┼──────┼────────────────────────────────────────────────────┼───────┤
│ GRE3000_3_T.json                                  │ 3041 │ 再要你命3000，有音标                               │ 高    │
├───────────────────────────────────────────────────┼──────┼────────────────────────────────────────────────────┼───────┤
│ GRE_equivalent.json                               │ 827  │ SE 等价词配对                                      │ 高    │
├───────────────────────────────────────────────────┼──────┼────────────────────────────────────────────────────┼───────┤
│ TOEFL_3_T.json                                    │ 4264 │ TOEFL 核心词                                       │ 中    │
├───────────────────────────────────────────────────┼──────┼────────────────────────────────────────────────────┼───────┤
│ SAT_3_T.json                                      │ 4464 │ SAT 核心词                                         │ 中    │
└───────────────────────────────────────────────────┴──────┴────────────────────────────────────────────────────┴───────┘

# 数据模型
┌─────────────┐         ┌──────────────┐
│  WordBook   │ 1───N   │ WordBookEntry│
│─────────────│         │──────────────│
│ id          │         │ bookId       │
│ name        │         │ wordId ──────┼──→ Word (共享)
│ exam (GRE/  │         │ sortOrder    │
│  TOEFL/SAT) │         │ chapter?     │
│ source      │         │ category?    │
│ description │         └──────────────┘
│ wordCount   │
│ structure   │  ← "sequential" | "thematic" | "frequency"
└─────────────┘

┌─────────────┐
│ StudyPlan   │  ← 用户的学习计划 (可以有多个活跃的)
│─────────────│
│ id          │
│ bookId ─────┼──→ WordBook
│ name        │  "GRE 3000 冲刺"
│ dailyNew    │  每天新词量
│ currentPos  │  学到哪了
│ isActive    │
└─────────────┘

┌─────────────┐
│ ReviewCard  │  ← 按 Word 而非按 Book (记忆是全局的!)
│─────────────│
│ wordId ─────┼──→ Word (唯一)
│ stability   │
│ dueDate     │
└─────────────┘

关键设计决策：Word 全局，ReviewCard 全局，StudyPlan 按书
```
有一个担心: 不同词书的词义是否会有差异? 如何 "merge" 维护一个高质量的词库?
直观感觉没啥问题, 先开始实现吧
```sh
[GRE] 再要你命3000:   3036 词 (sequential)
[GRE] 词以类记:       8384 词 (thematic) ← 语义簇，入门推荐
[GRE] 等价词:          827 组 (SE practice)
[TOEFL] 核心:         4264 词
[TOEFL] 词以类记:     3669 词 ← 难度适中 + 词根助记
[SAT] 核心:           4463 词
```
这里的词书构建方案是如何生成的?
```sh
# 数据源分层
┌─────────────────────────────────────────────────────┐
│ Layer 1: 已有 rich data (words.json, 6515 GRE 词)    │
│   来源: GRE_3.json (之前 build_worddb.py 生成)       │
│   内容: 完整释义/词根/助记/例句/同义词/反义词         │
│   地位: 主词库，永不被覆盖                           │
└─────────────────────────────────────────────────────┘
         │
         ▼ merge
┌─────────────────────────────────────────────────────┐
│ Layer 2: qwerty-learner 词书 (6 本)                  │
│   来源: 开源项目 public/dicts/*.json                  │
│   内容: spelling + 中文释义 + 音标(部分)              │
│   地位: 补充词条 + 提供词书顺序                       │
└─────────────────────────────────────────────────────┘
```
所以 Erudite/Erudite/Resources/Data/ 两个文件应该是持续维护的? 应该放进 git?
放进 git 的话, words.json 是不是用多行的 json 更好? 另外, 之前的 listIndex/unitIndex 是不是没用了?
另外, 
1. 面向 git 的话, 是不是对单词排序更好?
2. words_per_unit 是如何得到的?

目前的 words_per_unit 是如何设置的? 
- 一方面, 可能需要让用户能够设置? (需要吗? Learn 页面应该是随时可暂停的? 这样的话或许也不重要?)
- 另一方面, 不同的词书会有不同设置吗 (估计很多都是没有的?) qwerty-learner 是如何设置的
```sh
qwerty-learner: 全局设置为 20

# 你的直觉是对的 — 这个值不太重要，因为：
1. Learn 页面随时可暂停 — 不是"做完一个 Unit 才能退出"的模式，FSRS 本身就是 per-card 的
2. 进度是连续的 — "学到第几个词"由 wordListEntry.sortOrder + ReviewCard 状态决定，不需要 Unit 边界
3. 如果做 Unit，它纯粹是视觉分组 — "Chapter 3: 词 41-60"，帮助用户感知进度
```
将这一 feat 补充进 issue

## stats
下面, app 完整运行起来还差哪些部分?
```sh
# ❌ 完全未实现
┌────────────────────────────────────────┬───────────────────────────────────────────────────┐
│                  功能                  │                       说明                        │
├────────────────────────────────────────┼───────────────────────────────────────────────────┤
│ AI 实时教学 (解释/助记/上下文)         │ spec 里设计了 3-layer architecture，代码全是 stub │
├────────────────────────────────────────┼───────────────────────────────────────────────────┤
│ Quiz 模式 / SE 配对模式 / Speed Review │ 只有 flashcard 模式                               │
├────────────────────────────────────────┼───────────────────────────────────────────────────┤
│ 统计仪表盘 (学习曲线、retention rate)  │ 有数据采集但无展示                                │
├────────────────────────────────────────┼───────────────────────────────────────────────────┤
│ 自定义词书 (用户创建/导入)             │ 目前只有 builtin                                  │
└────────────────────────────────────────┴───────────────────────────────────────────────────┘

# 优先级建议
P0: 已经能用了 — 选词书 → 学新词 → 翻转 → 评分 → 下一个
P1: FSRS 真实实现 — 否则复习间隔不科学，学了等于没学
P2: Dashboard — 让用户看到进度反馈
P3: AI Teacher — 核心差异化功能
```
先来帮我实现实现简单的功能: Dashboard/Stats

- 首页 "Today" 目前默认进入 "All Books", 里面 1w+ 单词不是我想学的; 应该记忆我上次选择的书籍;
- 目前看不到背诵某本书的进度
```sh
Today 页现在显示：
┌─────────────────────────────────────────────┐
│ 📖 [GRE 再要你命3000 ▼]                     │
│                                             │
│   ✓ Learned: 156    ⟳ Due: 12    + New: 2880│
│                                             │
│   GRE 再要你命3000        156 / 3036 (5%)   │
│   ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│                                             │
│   [Start Learning]  [Review Due]  [New Words]│
└─────────────────────────────────────────────┘
```

存档进 done issue, 另外 FSRS, Quiz 模式 / SE 配对模式 / Speed Review 这些也创建 todo issue


## build app (release)
如何将 app 安装到本机? 这样就不用通过 Xcode 启动了.
安装之后数据会丢失吗?
// ~/Library/Application Support/Erudite/erudite.db
在 Xcode 中如何 build?

Build Configuration 之后, 下次按 "Run" 按钮运行的是 debug/release?
```sh
# 安装到 /Applications
在 Xcode 里改一下 Build Configuration：
- Product → Scheme → Edit Scheme (⌘<)
- 左侧选 Run → Info → Build Configuration 改为 Release
- ⌘B build
然后：
- Product → Show Build Folder in Finder（或 Xcode 菜单栏 Product → Reveal Build Products Folder）
- 把 Release/Erudite.app 拖到 /Applications
```

## mimic qwerty-learner
下面, 我觉得一个高优的需求是实现类似 qwerty-learner 形式的背单词模式
- 背景: 因为在电脑上背单词, 单纯看的记忆是很有限的, 我感觉 qwerty-learner 的模式, 通过肌肉记忆来背是一个思路
- UI 设计: 感觉可直接参考, 
  - 选择词书&章节之后, 进入拼写背诵页面, 检测键入的字符, 前缀匹配; 错误的话回退重新尝试
  - 显示内容: 基本内容是单词释义 & 单词 (感觉可以加一个显示单词完整卡片的功能? 类似现在的背诵模式); 默认自动发音;
  - 熟悉一个章节后, 可选择默写模式 -- 不显示单词字母, 通过释义+读音来拼写 (最好显示内容是可设置的)
  - 展示当前章节的overall 信息 (e.g. qwerty-learner 中点击可展开 word list; 预览上/下一个单词) -- 这一点设计在目前 flashcard 形式中也可以借鉴?
//  ~/.claude-internal/plans/hashed-snuggling-scroll.md
```sh
- ✅ 逐字母验证（正确→绿，错误→红闪 300ms 后重置）
- ✅ 自动发音（新词出现时）
- ✅ Dictation 模式（Tab 切换，隐藏未输入字母）
- ✅ 章节系统（20 词/章，可翻页）
- ✅ Word List 弹窗（查看当前章节所有词）
- ✅ 上/下一词预览
- ✅ 键盘快捷键（Tab=默写, R=重播, →=跳过, Esc=退出）
- ✅ 章节完成统计（词数 + 错误数）
```

1. 交互逻辑: 我发现只剩下 start/review 两种模式了, 之前 new 学新词的模式去掉了?
  1. 进入到 "Learn" 页之后, 设置为 Type 模式的话很多给之前背诵模式的特性似乎会干扰?
  2. 是否可以将两种模式拆成两个 tab 分开来实现呢?
2. Type Practice: 罗列测试的一些问题
  1. 目前似乎没有进度记忆的功能!
  2. 讨论: 和 FSRS 范式下的背诵是什么关系?
  3. bug: 目前右键可以跳过一个单词, 但是左键无法返回上一个; 
  4. 点击最下面的单词预览 / 在 wordlist 中也没法跳转到对应单词
  5. R 键 replay 显然和拼写模式冲突
  6. 某个 ch 错误之后的处理: 感觉可以作为配置项 -- 1. 错误的话清空当前前缀 (从头开始); 2. 当前的重试当前 ch 的模式. 另外, 键入错误的时候播放错误声音
  7. 之前说的 "显示当前单词完整card内容" 的功能好像没有 -- 类似 flashcard 背诵模式? 是不是可以继续用 space 键
// 先记录一下错误/typing 次数, 另外存到 DB 中, 后续在考虑如何融入 FSRS 体系中
```sh
# 架构调整
┌─────────────────────────────────┬──────────────────────────────────────────────┐
│              之前               │                     之后                     │
├─────────────────────────────────┼──────────────────────────────────────────────┤
│ Today / Learn / Library / Stats │ Today / Flashcard / Typing / Library / Stats │
├─────────────────────────────────┼──────────────────────────────────────────────┤
│ Typing 是 Learn 的子模式        │ Typing 是独立 tab，互不干扰                  │
└─────────────────────────────────┴──────────────────────────────────────────────┘

# Bug 修复 & 功能改进
┌─────────────────────────────────────┬──────────────────────────────────────────────────────────┐
│                问题                 │                           修复                           │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ 没有进度记忆                     │ ✅ 章节进度存 UserDefaults（per book）                   │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ 左键无法返回                     │ ✅ ← 返回上一个词                                        │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ Word list 不能跳转               │ ✅ 点击 word list 中任意词 → 跳转                        │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ 点击 prev/next 预览无反应        │ ✅ 可点击跳转                                            │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ R 键和拼写冲突                   │ ✅ 改为 ⌘R 重播发音                                      │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ 错误后只有"重试当前字母"一种模式 │ ✅ 可切换：retry char / reset word（按钮切换）           │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ 键入错误无声音                   │ ✅ NSSound.beep()                                        │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ 没有显示完整卡片的功能           │ ✅ Space 展开/收起完整 word card                         │
├─────────────────────────────────────┼──────────────────────────────────────────────────────────┤
│ ❌ 和 FSRS 关系不明                 │ ✅ 预留 // TODO: Record typing stats to DB，后续单独实现 │
└─────────────────────────────────────┴──────────────────────────────────────────────────────────┘
```

## fix shortcuts activation
关于快捷键激活:
- 对于 Flashcard/Typing 页面, 为什么有一个发光的框 (表示在当前区域内?), 这样才能进入快捷键模式? 是不是可以去掉
- 关联的交互上问题: 比如我使用 "Word List" 跳转单词后, 又没有进入选中状态 (无法输入, 快捷键也全部失效)


## optim typing features
1. 之前说 "拼写正确/错误" 的时候播放对应提示音的功能, 似乎没做
2. 目前是如何记录 typing 信息的? DB 设计如何?

- 目前错误的时候有提示音吗? 我好像没听到?
- 既然加入时间统计, 是不是应该像 qwerty-learner 一样有一个 "离线状态"? 
  - e.g. 任意按键进入键入模式; esc/窗口没有聚焦的话回到非键入模式 (单词也应该隐藏)

一些优化点:
- 目前 错误回退/错误继续 的模式似乎无法跨 session 保留, 应该在下一次 typing 模式的时候保留上次的配置;
- 进入/退出模式优化: 1. "任意键开始" 应该支持 space 按键; 2. 激活按键应该不能输入到单词上 (现在激活字符会变成第一个字母); 3. 非激活窗口 (我有多显示器) 状态下似乎没有进入退出模式
- 反馈优化: 我希望每个字符按下去有及时的反馈, 就像打字机一样 (qwerty-learner 就做的很好)
- 类似 qwerty-learner, 下面可以加一些统计指标以增添乐趣. e.g. 时间/WPM/输入数/正确数/正确率 -- 其中后面三个是字符级别的统计
- 优化 "默写" 体验: 目前是隐藏全部字符; 感觉可以借鉴 qwerty-learner, 包括 隐藏元音/辅音/全部隐藏 3 种模式, 渐进学习
- 类似 qwerty-learner, 一个章节结束的时候加一个简单的统计页面:
  - 显示 正确率/章节耗时/WPM
  - 列出所有单词 (错误的放在最前面)
  - 提示后续操作: 重复本章节/下一章节 / 默写 (设置为隐藏所有单词)
- 增加 "循环读音" 的功能
架构上, 我感觉这些配置项应该都是页面上可调整的, 跨 session 记忆 -- 类似 qwerty-learner 中配置是否显示释义, 三种默写模式切换, 是否循环读音?

发现一个问题: 为什么我在背 "toefl-ciyileiji" 的 "draw" 的时候, 上面仅显示了 "elicit", 没有中文 & 发音
// words.json 的问题

1. 目前 "检测当前窗口是否激活" 的功能似乎没有生效 -- 我点击了 macos 上其他 app 的时候, 计时没有停止, 也反复在读音;
2. "希望每个字符按下去有及时的反馈, 就像打字机一样" 这个功能也没实现, 是哪里的问题?

- 退出 typing 模式后, 计时似乎没有停止;
- "即时按键音效" 似乎没实现好? 现在直接所有按键都没声音了!

我重新到 Xcode run 测试了一下, 还是听不到按键效果音, debug 或者搜索看一下问题?
原来是因为设置了 "Alert volume"=0 的问题! 这个没想到, 介绍一下 macos 系统 / 应用开发中, 如何使用声音/有哪些配置?
```sh
# 两条通道
┌─────────────────────────┬───────────────────────────────────┬───────────────────────────────────────┐
│          通道           │             控制什么              │              API 走哪条               │
├─────────────────────────┼───────────────────────────────────┼───────────────────────────────────────┤
│ Output Volume (主音量)  │ 音乐、视频、app 自身音频          │ AVAudioPlayer, AVAudioEngine          │
├─────────────────────────┼───────────────────────────────────┼───────────────────────────────────────┤
│ Alert Volume (提示音量) │ 系统音效、通知音、NSSound(named:) │ NSSound, AudioServicesPlaySystemSound │
└─────────────────────────┴───────────────────────────────────┴───────────────────────────────────────┘

# macOS App 中的音频 API 层级
┌─────────────────────────────────────────────────────────┐
│ 最底层: Core Audio / AudioToolbox                        │
│   AudioServicesPlaySystemSound() — 走 Alert Volume      │
│   AudioQueue / AudioUnit — 走 Output Volume             │
└───────────────────────────────────┬─────────────────────┘
                                    │
┌───────────────────────────────────┴─────────────────────┐
│ 中间层: AVFoundation                                     │
│   AVAudioPlayer — 走 Output Volume ← 推荐用这个!        │
│   AVAudioEngine — 走 Output Volume (高级, 支持混音/效果) │
└───────────────────────────────────┬─────────────────────┘
                                    │
┌───────────────────────────────────┴─────────────────────┐
│ 高层: AppKit                                             │
│   NSSound(named:) — 走 Alert Volume ← 我们目前用的      │
│   NSSound(contentsOf:) — 也走 Alert Volume               │
└─────────────────────────────────────────────────────────┘
```

# Notes
[todo]
- ai: 
  - [ ] chatbot sidebar; daily review
- [x] FSRS: 基础实现, 后续待优化
- feat: 
  - [ ] feat: dictionary
  - [ ] qwerty-learner
- basic
  - [x] 安装到本机 -- 直接 build release
  - [x] vocabulary?
  - [x] keybaord shortcuts
  - [ ] github action
- view
  - [x] stats 页面


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
- features
  - FSRS: 核心记忆逻辑, @Erudite/Erudite/Engine/FSRS/FSRSEngine.swift
    - ⚠️  当前是 stub，还没实现完整 FSRS-5
  - keybaord shortcuts
  - 自动语音播放
  - 多词书 (workbook)
    - 词义数据: 
    - 词书 (list) 数据源: #qwerty-learner
  - view: stats (dashboard)
- typing (对标 qwerty-learner)
  - feat: 循环读音; 切换英音/美音
  - feat: 实时输入统计: WPM, 输入/正确数
  - feat: 隐藏元音/辅音/全部字符
  - feat: 章节小结
  - feat: 键入错误回退
  - feat: 激活/退出 typing 状态
