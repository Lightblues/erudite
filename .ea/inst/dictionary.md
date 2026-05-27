
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