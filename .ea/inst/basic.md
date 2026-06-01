
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

## fix xcode warning
下面是 Xcode 中出现的 error/warning, 分别是什么意思? 是否需要修复?
```sh
# 根本原因(一句话)
项目设了 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,所以所有类型默认隐式带 @MainActor(包括 Word、ReviewCard、ReviewLog、WordBook、FSRSParameters)。但 DatabaseService 被标成 nonisolated(unsafe) 想跨线程跑数据库 IO——于是只要它在 nonisolated 方法里碰这些 MainActor 类型(初始化、Codable 编解码),就违反 Swift 6 的隔离规则。
```
解释一下  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, 是什么意思, 然后帮我修复
```sh
# 关于 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor 的小结

这个设置的"哲学"是:App 大多数代码本来就跑在主线程,与其逐个标 @MainActor,不如默认全标,例外用 nonisolated 显式退出。

实践中只有两类东西需要 nonisolated:
1. 纯数据值类型(本次修复的全部 model)— 它们没有共享可变状态,任何线程都能安全读写。
2. 明确要跑后台的服务(本次的 DatabaseService)— GRDB 的 IO 必须可以跨线程,不能被 MainActor 锁死。

UI 层(View / ViewModel / @Observable)就保持默认的 MainActor,不用动
```

@.ea/spec/lessons.md 上面修复 MainActor 的经验写入其中

create new branch then merge. 核心内容是 ai chat 系统 & 修复

## fix vscode (macos permission)
修复下面 CC 的权限配置. 我应该已经配置为 no sandbox 了
```sh
!  ls /Users/frankshi/Downloads
Permission denied: /Users/frankshi/Downloads - code: 13

Skipped 1 directories due to permission denied:
  /Users/frankshi/Downloads
```
```sh
# 原因: vscode 的权限问题!
Option A — Downloads folder only:
System Settings → Privacy & Security → Files and Folders → expand Visual Studio Code → enable Downloads Folder.

Option B — Full Disk Access (broader, simplest):
System Settings → Privacy & Security → Full Disk Access → toggle on Visual Studio Code (add it with + if absent).

After toggling, fully quit and reopen VS Code (Cmd+Q — a window reload isn't enough; the TCC grant is read at process launch).

I can open the right pane for you:

open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"        # Full Disk Access
open "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders" # Files and Folders
```
