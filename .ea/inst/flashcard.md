
## fix window height bug
可以了!
下面, 修复 bug: 
- 在 Flashcard 页面, 我 space 展开词义/左键后退的时候, 有时候会自动调整整个 erudite 窗口的大小 -- 甚至超过桌面高度, 这是为什么?
  - 这个 bug 之后, 快捷键功能也失效了
- 第二次 space (toggle 词义) 之后, 现在自动跳到下一个单词了? 我感觉合理的逻辑应该是仅 toggle 而非到下一词? 或者类似 Typing 页作为配置项可设置

似乎没解决? 高度又超过桌面窗口高度了
```sh
1. 移除 .fixedSize(horizontal: false, vertical: true) — 这个修饰符告诉 SwiftUI "用我的理想高度"，会导致窗口跟着内容变大
2. 移除 .animation(.easeInOut, value: isRevealed) — 这是根本原因。它作用在整个 VStack 上，当 isRevealed 变化时会动画化整个容器的 frame 变化，macOS 会响应这个变化去调整窗口大小
3. 添加 .windowResizability(.contentSize) + minWidth/minHeight — 约束窗口尺寸范围，防止无限增长
```
## optim flashcard ui
我觉得应该对齐 typing & flashcard 的 UI & 快捷键
快捷键:
- 我觉得可共用:
  - space: 逻辑一致, toggle 单词卡
  - <-, ->: 左右键切换单词
  - esc: 目前 flashcard 里面的逻辑是 "停止", flashcard 里面也是类似的, 没必要直接退出
- 特有逻辑
  - r/q: 因为没有输入占用, 先保留是合理的
  - 1234/jkl;: 特有逻辑, 保留
UI: 
- 目前 typing 页通过 space 展示的单词卡应该不是同一个? 是不是可以复用 flashcard 的组件? 
  - 也有组件大小导致的窗口变化问题
- 学习逻辑: 目前是只能 space 展开单词之后才能选择 1234, 这样的设计理念是什么? 在遮蔽状态可以选择吗?
- 每次学习的词表: 同 typing, 展示当前学习的词表 (组件也可复用?)
- 上方选项:
  - accent: 同 typing 支持切换; 
  - Loop audio: 感觉也应该支持

新发现2 个 bug:
1. 在 esc 进入 "pause" 状态后, flashcard 页面显示 "paused" 但是按任意键没反应 (有按键音效)
2. 类似的一个 bug: typing 页面从查词页面 esc 进入 pause 页面后, 按任意键都没有反应 (听到了系统提示音, 但是页面始终显示 "任意键开始")
此外, 我觉得可以优化的:
- typing 页: 两次 esc 之后回退到 Today 页面, 我觉得没必要? 到这个时候我倾向于鼠标操作
- flashcard 页: 
  - 我想要一个类似 typing 页的词表的功能 -- 检查本次学习的核心内容有哪些;
  - 也可以加前后词预览的功能
  - 一个 list 完成后, 也应该给一个总结页面, 看看学习成果
```sh
# Bug 修复
┌────────────────────────┬─────────────────────────────────┬────────────────────────────────────────────────────┐
│          Bug           │              原因               │                        修复                        │
├────────────────────────┼─────────────────────────────────┼────────────────────────────────────────────────────┤
│ Flashcard idle         │ idle 状态下未匹配的键返回       │ 所有键返回 .handled，letter/space 触发 activate()  │
│ 按键无反应(有 bonk 音) │ .ignored，系统播放错误音        │                                                    │
├────────────────────────┼─────────────────────────────────┼────────────────────────────────────────────────────┤
│ Typing                 │ popover 关闭后焦点丢失          │ 添加 .contentShape(Rectangle()).onTapGesture {     │
│ 查词后按键无反应       │                                 │ isFocused = true } 点击恢复焦点                    │
├────────────────────────┼─────────────────────────────────┼────────────────────────────────────────────────────┤
│ Typing Esc 两次回      │ 不必要的退出行为                │ 移除 idle 状态 Esc → Today 逻辑，Esc 只做 pause    │
│ Today                  │                                 │                                                    │
└────────────────────────┴─────────────────────────────────┴────────────────────────────────────────────────────┘
```

基本修复了, 还有的 bug:
- 在 flashcard 页面, pause 页面还是卡卡的 -- 有时候需要鼠标点一下才能通过按键来预览/标记单词
  - 或者是鼠标点击 word list, 然后点击 flashcard 区域之后, 又无法按键操作了
另外, 核心逻辑应该有对应的鼠标操作: -- 相较于 typing 页面肯定要键盘优先; 做一个给用户用的 GUI 产品肯定要求鼠标能够执行核心操作!
- 标记单词: 已经有了
- 反转单词: 目前确实该能力
另一个 bug: 我发现 flashcard 页面可能会出现重复的单词! 例如在我上一个 list 中出现了两次 membrane


## rewrite with `KeyCaptureView`
还有有 bug. 我复现的一个流程是: 在单词详情页 esc, 然后任意键进入后, 所有的按键似乎又都无效了
- 梳理一下, 为什么反复出问题?
- 可以有一个简单的模型来处理按键响应吗? 简化一下问题! (swift/其他桌面 app 有什么最佳实践)
```sh
# 根本性重构：从 @FocusState 迁移到 NSViewRepresentable

为什么之前反复出问题？
┌──────────────────────────────────────┬────────────────────────────────────────────────────────────────┐
│ SwiftUI 的 @FocusState + .onKeyPress │                              问题                              │
├──────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
│ Popover 创建新窗口                   │ macOS 把 firstResponder 给了 popover 的 NSWindow，关闭后不恢复 │
├──────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
│ Button 点击                          │ 内部的 NSView-backed 控件抢占了 firstResponder                 │
├──────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
│ 用 timer hack 补救                   │ 与 SwiftUI 的 layout pass 竞态，不确定性                       │
└──────────────────────────────────────┴────────────────────────────────────────────────────────────────┘

新方案：KeyCaptureView (NSViewRepresentable)
┌─ ZStack ──────────────────────────────┐
│  ┌─ UI Layer (SwiftUI Views) ─────┐   │
│  │  cards, buttons, popovers...   │   │
│  └────────────────────────────────┘   │
│  ┌─ KeyCaptureView (NSView) ─────┐   │
│  │  • acceptsFirstResponder = true│   │
│  │  • resignFirstResponder → 自动 │   │
│  │    重新抢回 (1 runloop cycle)  │   │
│  │  • windowDidBecomeKey → 抢回   │   │
│  │  • keyDown → 转发给 SwiftUI   │   │
│  └────────────────────────────────┘   │
└───────────────────────────────────────┘

# 核心机制：
- resignFirstResponder() 被调用时（button/popover 抢焦点），在下一个 runloop cycle 自动重新 makeFirstResponder(self)
- 例外：如果新的 responder 是 NSTextView（文本输入框），则让步
- windowDidBecomeKey 通知 → popover 关闭后立即恢复
- 所有 timer hack、onChange(of: isFocused) 等补丁全部移除
```
KeyCaptureView 的作用是什么?
```sh
# 问题本质

macOS 的键盘事件是通过 First Responder 链 传递的：

NSWindow → firstResponder (某个 NSView) → keyDown:

SwiftUI 的 .onKeyPress 依赖 @FocusState 把某个 SwiftUI view 设为 first responder。但：

- Popover 弹出 → 创建新 NSWindow → firstResponder 移走
- Button 点击 → NSButton 变成 firstResponder
- Popover 关闭 → 没人把 firstResponder 还回来

结果：键盘事件发到了"虚空"，系统播放 bonk 提示音。

KeyCaptureView 做了什么

它是一个透明的 NSView，做三件事：

1. acceptsFirstResponder = true — 告诉系统"我能接收键盘"
2. resignFirstResponder() → 自动重新抢回 — 当 button/popover 试图抢走焦点时，在下一个 runloop cycle 执行 window.makeFirstResponder(self) 把自己设回去
3. windowDidBecomeKey → 恢复 — popover 关闭后窗口重新变为 key window 时，立刻重新抢焦点

等价于一个"焦点钉子" — 焦点被抢走后立即弹回来，确保键盘事件永远到达我们的 handler。
```


## fix `InteractiveText` click
修改之后, 预期功能正常了, 但发现一个新的 bug: 之前的 按键打开 word 详情的功能失效了 -- 所有的单词虽然有下划线标记, 但无法点击
// 原因：KeyNSView 在 ZStack 最上层，虽然透明但默认仍接收鼠标点击（hitTest 返回自身），导致下面的 SwiftUI onTapGesture 全部被拦截。

总结我们之前的实现, 更新 spec 集; 另外这一 feat 是不是可以新加一个 issue 文件?
