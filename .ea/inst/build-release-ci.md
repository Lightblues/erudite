
## build dmg
帮我本地 release 一个安装包, 我发给别人使用
// 分发场景:你只有 Apple Development 证书(没有 Developer ID Application),意味着这个包发给别人会触发 macOS Gatekeeper 警告
```sh
┌──────────────────────┬─────────────────────────────┬────────────────────────────────────────────────────────────────────────────┐
│                      │   Ad-hoc (codesign -s -)    │                           Apple Development 证书                           │
├──────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
│ 谁能装?              │ 任何 macOS                  │ 理论上仅你授权过的设备(provisioning profile);实际上一般机器也能装,但       │
│                      │                             │ Gatekeeper 会更警惕                                                        │
├──────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
│ Gatekeeper 警告      │ "无法验证开发者" →          │ "由 frankeasonshi@gmail.com 签名" → 也可能被拦,需右键打开                  │
│                      │ 右键打开一次                │                                                                            │
├──────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
│ 接收者操作           │ 一样(右键打开 / xattr -d)   │ 一样                                                                       │
├──────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
│ 证书过期影响         │ 永不过期                    │ 1 年后过期,过期后用户每次重启可能重新拦                                    │
├──────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
│ 改动 entitlements    │ 自由                        │ 受 provisioning profile 限制                                               │
│ 易用性               │                             │                                                                            │
├──────────────────────┼─────────────────────────────┼────────────────────────────────────────────────────────────────────────────┤
│ 给的"安全感"         │ 看到"未签名"                │ 看到"由 ___ 签名"                                                          │
└──────────────────────┴─────────────────────────────┴────────────────────────────────────────────────────────────────────────────┘
对你这种朋友间分发:Apple Dev 证书除了"看起来更正经"没有任何实际优势,反而 1 年后会过期。Ad-hoc 是更务实的选择。

# 在 erudite 项目根执行(等价于 commands above):
rm -rf /tmp/erudite-release && mkdir -p /tmp/erudite-release && cd /tmp/erudite-release && \
xcodebuild -project ~/Projects/app/erudite/Erudite/Erudite.xcodeproj -scheme Erudite -configuration Release \
  -derivedDataPath ./DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build && \
APP=DerivedData/Build/Products/Release/Erudite.app && \
codesign --force --deep --sign - --options runtime \
  --entitlements ~/Projects/app/erudite/Erudite/Erudite/Erudite.entitlements "$APP" && \
mkdir -p dmg-staging && cp -R "$APP" dmg-staging/ && ln -s /Applications dmg-staging/Applications && \
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist") && \
hdiutil create -volname "Erudite ${VERSION}" -srcfolder dmg-staging -ov -format UDZO "Erudite-${VERSION}.dmg" && \
codesign --force --sign - "Erudite-${VERSION}.dmg" && \
cp "Erudite-${VERSION}.dmg" ~/Desktop/
```
参考 @/Users/frankshi/Projects/app/nexus/nexus-swift/project.yml , 1. 是否可以配置 project.yml 会否更方便? 2. 要求系统 13.0 是否就可以了?
// 为什么不能再降到 13.0?@Observable 宏需要 macOS 14。整个 Erudite 的 ViewModel 层都基于它,降级 = 状态层重写。14.0 是技术下限。

## CI
下面, 考虑构建 release & 上线 brew 的方案, 参考 @/Users/frankshi/Projects/app/nexus/.github/workflows/build.yml @/Users/frankshi/Projects/app/nexus/.github/workflows/update-tap.yml
先跟我讨论一下方案, 暂不实现
```sh
 ● Version 怎么提供给 CI?
   → 换成 XcodeGen 会怎样?
 ● DMG 架构?
   → universal 在安装之后, 相较于 arm64 版本有什么差异?
 ● 打包脚本位置?
   → 抽出 scripts/build-dmg.sh (推荐)
 ● Build trigger?
   → Tag + manual (推荐)
```
```sh
# CI 里读 version 的事,直接 grep MARKETING_VERSION 一行 awk 就解决了:
VERSION=$(awk -F'= ' '/MARKETING_VERSION =/ {gsub(";", "", $2); print $2; exit}' Erudite/Erudite.xcodeproj/project.pbxproj)
```
我 clone 到 /Users/frankshi/Projects/app/homebrew-tap/ 了, 你直接帮我操作
```sh
# merge 这个 PR 到 main 之后
git tag erudite-v1.0.0
git push origin erudite-v1.0.0
gh run watch

# 朋友装:
brew tap lightblues/tap
brew update          # 拉所有 tap 的最新 commits,包括 lightblues/tap
# brew install --cask erudite
brew install --cask lightblues/tap/erudite
```

1. .github/workflows/update-tap.yml action 的作用什么? 触发时机?
2. 测试了 brew 安装链路 似乎没找到? 因为没更新吗?
```sh
# /update-tap.yml 作用?
它是 build.yml 里"自动更新 tap"那段逻辑的手动备胎。当某些异常发生需要重写 cask 时,不需要重打 release,只用一条命令就能把 tap 重新对齐。
┌────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────┐
│                            场景                            │                       用什么                       │
├────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────┤
│ 正常发版                                                   │ git tag erudite-v1.0.0 && git push --tags →        │
│                                                            │ build.yml 全自动跑完                               │
├────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────┤
│ build.yml 里"Push cask update"挂了(比如 token 过期、tap    │ update-tap.yml                                     │
│ repo 临时 401)                                             │                                                    │
├────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────┤
│ 手工编辑了 GitHub Release(改了 release notes、重传 DMG)→   │ update-tap.yml                                     │
│ sha256 变了                                                │                                                    │
├────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────┤
│ tap 仓被人手改后想强制重新拉取                             │ update-tap.yml                                     │
└────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────┘
```
// brew install --cask lightblues/tap/erudite

更新配置, 以解决之前 github actions 报的 warning (不要 commit)

## `/release` command
可否将 release 相关写成一个 Claude Code command 或者 skill?
感觉有点复杂了, 我原本预期的行为是:
- /release patch|minor|major 能够快速帮我更新版本号发布; 快速流程
- 比较 pr & release 流程, 它们的关系是什么? 先 pr 再发版?
- 有必要 gh run watch 吗? 这个会不会时间比较长, 阻塞后续的开发? 一般情况发布应该没啥大问题的话, 直接在云端跑即可, commands 就可以结束了?
- 在 CC command 通过 !`xxx` 的语法注入 context 信息, 减少 agent 的执行链路, 加速
Confirm 这一步有必要加吗? 最简化的话, agent 跑完, 告诉我版本号变化即可
