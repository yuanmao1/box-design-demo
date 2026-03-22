# 手工编写模板

## 目标

手工模板仍然是最灵活的方式，适合：

- 有参数化需求
- 有圆弧或更复杂边界
- 需要显式控制 panel 拓扑和 3D 预览语义

## 最小模板结构

每个模板文件建议包含：

- `descriptor`
- `Instance`
- 本地 `PanelKey`
- `create(...)`
- 至少一个模板行为测试

可参考：

- [simple_two_panel.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/simple_two_panel.zig)
- [mailer_box.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/mailer_box.zig)

## 推荐开发顺序

1. 先把业务参数收敛成明确数值。
2. 明确有哪些 panel，以及每个 panel 的边界。
3. 明确哪些 panel 之间通过 fold 相连。
4. 再导出 cut/score linework。
5. 最后注册到 [src/mod.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/mod.zig)。

## 常用 helper

模板辅助函数在 [wrench.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/wrench.zig)：

- `initRectPanelSet(...)`
- `initRectPanelStrip(...)`
- `scoreSegmentsForStrip(...)`
- `foldChainRightToLeft(...)`
- `appendCutLinework(...)`
- `appendScoreLinework(...)`
- `initPanelBySegments(...)`
- `roundedFlapSegments(...)`
- `annularSectorSegments(...)`

更具体的使用说明见 [wrench-guide.md](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/docs/wrench-guide.md)。

一个重要经验是：

- `appendCutLinework(...)` 不是“默认正确答案”
- 如果真实刀线应该是一条整体外轮廓，不要把每个 panel 都单独导出成 cut
- helper 只是降样板，不能替代 linework 语义判断

## 什么时候不建议手写

如果你的输入已经是“识别好的刀线关系”，例如：

- 每条线段的坐标
- 哪些闭环构成 panel
- 哪些对应 score/fold

这时优先考虑 spec 中间描述，再用 [compiled_spec.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/compiled_spec.zig) 编译期转模板，而不是继续手写大量重复 Zig。
