
## feat: dictionary
参见: spec 体系 @.ea/spec/README.md ; issues @.ea/issues/
我们之前完成 flashcard/typing 形式的背单词功能, 我感觉还需要补充的一个重要功能是 "词典": 对于页面中所有出现的英文单词, (如果在词典中有的话) 都应该是可交互的 -- 我点一下之后弹出单词窗口 (类似 flashcard 中按下 space) 可以查看词义;
如果没有出现的话, 感觉可以调用欧陆的 urlschema 来跳转 (或调用 api 来获取词义)?
```sh
· 交互方式偏好: 用户点击单词时, 应该如何触发词典查看? → 单击即弹出 (Recommended)
· 对于词库中没有的单词, 如何处理 fallback? → 先本地, 无结果再跳欧陆
· 需要在哪些页面/场景优先支持这个功能? → 这三种方式处理起来的难易程度如何?
```
// ~/.claude-internal/plans/harmonic-swimming-feather.md

测试了一下, 我发现对于 "parasitic" 一词, 
- 解释里面的 "living" 等简单词跳转到了 eudic, 应该是词库中没有?
- 对于下面的 parasitic/fungi, 应该是词库中有的, 但是有概率出现这种显示不出来的情况, 只有一个圆圈, 是在加载吗? 
- 再下面的同义词 autocious, 无法单击显示词义了
疑问: 目前显示词义的功能是单层的 -- 只能在指定页面点击查看; 能够支持多层呢? 在词义页面, 对于我不熟悉的词也应该能够查看

## fix empty popover
如图: 还是有 "空圆圈 popover" 的问题, 如何 debug? 搜索有相关问题吗?
```sh
popover(item:) 确保：
- popoverWord = nil → popover 不显示
- popoverWord = someWord → popover 显示，且 word 参数保证有值
```

## ext dictionary
下一步, 我想优化一下当前的词库, 帮我调研一下:
- 参考 @.ea/spec/data.md 和处理脚本 @scripts/ 我们目前的数据主要是从 `GRE_3.json (新东方, 6515 words)`  里面来的 -- 因为整体的数据字段最全
- 然而, 随着我们构建了 multibook 支持选择不同的词书 (计划), and 支持了点击查看词义的功能, 这些数据显然不够了;
- words 数据作为 "single source of truth", 需要能够覆盖更多词书中所包含的单词 -- 定位变成了 "针对 erudite app 优化的字典"!
- 首先, 调研一下目前网络上有哪些高质量的词典?
  - 之前调研的时候看到有 [ECDICT](https://github.com/skywind3000/ECDICT) 私人维护的;
  - 看到有 [欧陆](https://docs.eudic.net/1/jin-jie-gong-neng/url-scheme); [有道](https://ai.youdao.com/DOCSIRMA/html/dictionary/api/ydcd/index.html) 有 api
  - 或者, 直接转换更权威的词典/wiki? 调研一下?
- 然后, 从架构设计上, 原本的每个 word 的数据结构合理吗? 是否需要扩充? e.g. 更多的例句, 丰富的词义等
  - 基本宗旨: 保留尽可能多/权威的词义, 方便背诵
  - 另外, 反思一下, 之前讨论的 "single source of truth" 词库合理吗? 是否需要兼容不同的词书的词义 (e.g. 面向不同考试做侧重)
  - 背景: 我背单词主要是希望日常阅读/使用, 不是功利备考
你可以 clone repo 到 /Users/frankshi/Projects/_inbox/repo; 下载数据到 data/ 目录; 写相关脚本到 scripts/ 目录

为了避免打包过多词汇到 app 里面, 是不是可以仅包含必要词汇? 性能也好一点
其他词汇, 在使用过程中, (尽量使用公开 app) 动态增加到数据库中
- 实现类似 cache 机制, 新查的词加入进来;
- 修改之前的查词功能 -- 相较于跳转到 eudic (体验割裂), 默认读取 api 内部显示 (也可以在 popup 页支持跳转 eudic?)
- 数据结构页按需拓展
```sh
· 对于本地词库中没有的词, 用哪个 API 动态查询? → 你可以先测试验证一下!
· App 内置词库的范围应该多大? → 什么是 BNC/COCA? 你推荐如何?
```
```sh
# 新架构：动态词典 + API Cache

点击词 → 本地 DB (13K 词) → 命中? → popover ✅
                           → 未命中 → Free Dictionary API (async)
                                       → 成功: 解析 → 存入 DB → popover ✅
                                       → 失败: "Not Found" popover + Eudic 链接
```

## explore MW api & youdao etc
我申请了 Merriam-Webster's 的两个 api key (应该可以免费用 1000/day? 正式发布的话作为配置要求填入即可)
- 质量会不会更高一些? 据说比较权威
- 有必要切换吗? 或者两个 api 排优先级?
```sh
https://dictionaryapi.com/account/my-keys
https://dictionaryapi.com/api/v3/references/collegiate/json/test?key=xxx
https://dictionaryapi.com/api/v3/references/thesaurus/json/reflection?key=xxx
```

我觉得设置优先级 MW 更高, 然后 word source 检查 (如果之前记录的是其他 API 的, 再拉 MW 的质量更好以替换?)
- API: 我感觉还是别硬编码; 后面还要引入 AI modle api, 应该一开始就建立好规范配置项管理
  - 虽然预期个人使用为主, 但想要发到 github 上开源
  - 一般 swift 这类 api key 的规范如何? 如何保存?
  - 我之前开发的一个方案是将所有配置项统一放到 .yaml 文件中, 人和 AI 看都比较方便
```sh
# API 优先级

点击未知词
  ↓
① MW Collegiate API (释义 + 例句 + 词源)
   + MW Thesaurus API (同义词/反义词)
  ↓ 失败 (无 key / 限额 / 网络错误)
② Free Dictionary API (fallback)
  ↓ 也失败
③ "Not Found" popover + Eudic 链接

数据源升级机制

- 每个缓存词带 tags: ["source:mw"] 或 ["source:free_dict"]
- 当发现本地缓存来自 Free Dict 且 MW key 可用时，后台静默升级为 MW 数据
- insertCachedWord (IGNORE) 不覆盖已有丰富词条
- updateCachedWord (REPLACE) 用于 source 升级
```

发现一个问题: 因为 MW 的词意思都很多, popup 页面容纳不下会超长;
- 是否所有释义都是必要的? 精简一下? (点击展开)
- 除了跳转 eudic, 是不是也可以加一个跳转该词对应 MW 网页版的 link?

我想了一下, 词义直接用 MW 的不是很合适 -- 一个 quiet 能有很多词义, 在 UI 上展现出来只有 `quality or state of being quiet or calm` 这个名词词义了, 有点冷门, 不利于学习.
- 从中文母语者学习背诵的视角, 我感觉那些词书里面精选的常用词义/中文解释等, 对于初学者比较简单;
- MW 或者类似专业词典, 应该作为"二级"备选释义, 供用户参考
又回到了一开始的问题: 数据构建应该如何选择相对合适的数据源?
我感觉没必要直接改 app, 是不是可以用 scripts, 基于不同数据源处理得到各 100+示例, 然后我来看看做选型?
```sh
# 各源特点总结
┌─────────┬───────────┬─────────┬───────────┬──────────┬─────────┬──────────────┐
│   源    │ 中文释义  │ 英文释  │   例句    │ 助记/词  │  频率   │     适合     │
│         │           │   义    │           │    源    │         │              │
├─────────┼───────────┼─────────┼───────────┼──────────┼─────────┼──────────────┤
│ GRE_3 ( │ ✅ 精选常 │ ✅ 简洁 │ ✅ 有中英 │ ✅ 助记  │ ✗       │ 主学习数据   │
│ 新东方) │ 用义      │         │ 对照      │          │         │              │
├─────────┼───────────┼─────────┼───────────┼──────────┼─────────┼──────────────┤
│ ECDICT  │ ✅        │ 一般    │ ✗         │ ✗        │ ✅ BNC/ │ 补全覆盖+频  │
│         │ 全面多义  │         │           │          │ COCA    │ 率           │
├─────────┼───────────┼─────────┼───────────┼──────────┼─────────┼──────────────┤
│ MW API  │ ✗         │ ✅✅    │ ✅        │ ✅✅     │ ✗       │ 二级深度查阅 │
│         │           │ 最权威  │ 嵌入释义  │ 词源     │         │              │
└─────────┴───────────┴─────────┴───────────┴──────────┴─────────┴──────────────┘
```

再测试一下 [有道 api](https://ai.youdao.com/DOCSIRMA/html/dictionary/api/ydcd/index.html)? 
// 好吧, 不支持在线开通!

## final answer: ai enreich
我感觉不能在这个方向上折腾太久了. 基本思路:
- (权威但不适合快速记忆背诵) 调用/跳转到 MW 词典;
- 快速方案 (面向中文学习者), 有两点:
  - 方案 1: 处理 ECDICT 或者其他的词库资料, 初步补全已有词表的信息
  - 方案 2: 现在 AI 能力本来就很强, 我下面有个 API 可以快速调用, 在处理目前这些词单的时候, 可以批量先跑一遍, 把所以的信息都补上
    - 注意下面 API 仅通过 openai chat.completions 格式的流式调用
    - 你需要构想好所需输出的内容/prompt?
  - 对于这两个方案, 你先用 python 写个脚本, 验证一下脚本? 采用 uv add 包管理

合理的, 帮我补全一下目前的词表 (另外有额外的后续可用的字段也可以补上, 如果不显著增加体积的话?)
然后实现一下 AI 补全脚本, 我感觉可以 10 左右并发后台跑着, 注意将API 相关参数放到 .env 中避免 git

我记得之前讨论的一个方案是, words.json 纳入到 git 中, 通过 indent 形式 (而非单行) 来避免每次 git diff 过多? 这合理吗?
```sh
┌─────────────────┬───────────────┬────────────────────────────┐
│      格式       │     大小      │      Git diff 友好度       │
├─────────────────┼───────────────┼────────────────────────────┤
│ 紧凑单行 (当前) │ 5.7 MB        │ ❌ 任何改动 = 整个文件变化 │
├─────────────────┼───────────────┼────────────────────────────┤
│ indent=2        │ 9.3 MB (+63%) │ ⚠️ 改一个字段触发多行      │
├─────────────────┼───────────────┼────────────────────────────┤
│ 每词一行        │ 5.7 MB        │ ✅ 改一个词 = 变一行       │
└─────────────────┴───────────────┴────────────────────────────┘
最佳方案：每个 word 对象压缩为一行，外层结构有换行。 有效 JSON + git 只 diff 变化的词 + 体积不变。
```

这样的设计合理吗? (想维护 words 的更新过程);
另, data/ai_enriched_words.jsonl 两个文件是不是不需要放进 git?
```sh
# 数据更新流程
┌────────────────────────────────────────────────────┐
│                                                    │
│  data/raw/ (git-ignored)                           │
│  ├─ GRE_3.json, ECDICT, ...                       │
│  │                                                 │
│  ▼                                                 │
│  scripts/build_worddb.py → words.json v2 (6.5K)   │
│  scripts/build_multibook.py → words.json v3 (13K) │
│  scripts/enrich_ecdict.py → 补全音标/频率/标签      │
│  │                                                 │
│  ▼                                                 │
│  data/ai_enriched_words.jsonl (git-ignored, 中间产物)│
│  scripts/enrich_ai.py → 生成 AI 数据               │
│  scripts/merge_ai_enrichment.py → 合并到 words.json │
│  │                                                 │
│  ▼                                                 │
│  Erudite/.../Resources/Data/words.json  ← 入 git   │
│  (最终产物, single source of truth)                 │
│                                                    │
└────────────────────────────────────────────────────┘
```

我设置了环境变量, 替换成了一个更轻量的模型 `qwen3.6-35b-a3b-fp8`, 重新跑一下 enrichment, 看看效果是否有退化?
我感觉整体稳定性肯定没有 `gemini-3.1-flash-lite` 好, 我切回去了, 现在帮我全量跑一下

现在跑了一批结果出来了, 帮我执行 merge 操作, 然后结合我们上面的讨论, 更新 spec 文件集
