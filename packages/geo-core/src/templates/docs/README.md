# Templates Docs

这里集中放 `packages/geo-core/src/templates` 的说明文档，分成三类：

- 手工编写模板：
  入口是 [manual-template-authoring.md](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/docs/manual-template-authoring.md)
- `wrench` 辅助函数：
  入口是 [wrench-guide.md](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/docs/wrench-guide.md)
- 让 AI 直接产出模板：
  入口是 [ai-json-template-authoring.md](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/docs/ai-json-template-authoring.md)
- 让 AI 产出的 JSON 落到内部 spec：
  入口是 [ai-template-spec-authoring.md](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/docs/ai-template-spec-authoring.md)
- 让 AI 先看图再产出中间描述：
  入口是 [image-to-template-prompt.md](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/docs/image-to-template-prompt.md)

建议的使用顺序：

1. 先读手工模板文档，明确 `Panel/Fold/StyledPath2D` 的语义边界。
2. 如果要让 AI 生成模板，优先让它输出 JSON，不要直接写大量 Zig 几何代码。
3. 如果输入是刀线图图片，先用图像提示词让 AI 输出结构化 JSON，再通过生成器落到 spec。
