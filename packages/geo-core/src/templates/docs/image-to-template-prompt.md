# 图像到模板中间描述提示词

下面这份提示词适合给多模态模型，目标不是直接生成完整模板实现，而是生成 `geo-core` 可消费的 JSON 中间描述。

```text
你现在是包装结构识别助手。你的任务是读取我提供的刀线图，输出一个严格合法的 JSON，用于生成 packaging template。

你的目标不是把所有细节一次做完，而是先完成大部分繁琐的结构识别工作，保留少量可人工微调的位置。

输出要求：
1. 只输出 JSON，不要输出 Markdown，不要输出解释。
2. package_kind 固定为 "folding_carton"。
3. 所有坐标必须在同一 2D 平面坐标系下。
4. 如果更稳定，可以输出相对坐标，例如 0..1、0..100 或 0..1000。
5. panels 中每个 boundary 都必须是按顺序排列的闭合 segment。
6. folds 只在两个 panel 共享同一条铰线时输出。
7. linework 必须尽量区分 cut、score、guide。
8. 能确定是圆弧就输出 arc；能确定是三次曲线就输出 bezier；不确定时再退化成 line。
9. 如果无法确定某条线的语义，不要猜；把它放到 "guide" linework，留给人工微调。

JSON schema:
{
  "key": "folding_carton.<template_name>",
  "label": "<Human Readable Name>",
  "package_kind": "folding_carton",
  "numeric_params": [
    {
      "key": "target_width",
      "label": "Target Width",
      "default_value": 120
    }
  ],
  "normalization": {
    "target_size": {
      "x": { "param": "target_width" },
      "y": { "value": 80 }
    }
  },
  "panels": [
    {
      "name": "front",
      "boundary": [
        { "from": { "x": 0, "y": 0 }, "to": { "x": 1, "y": 0 } },
        {
          "kind": "arc",
          "center": { "x": 1, "y": 0.5 },
          "radius": 0.5,
          "start_angle": -1.5707963267948966,
          "end_angle": 1.5707963267948966
        }
      ],
      "accepts_content": true
    }
  ],
  "folds": [
    {
      "from_panel": "front",
      "to_panel": "back",
      "from_segment_index": 1,
      "to_segment_index": 3,
      "angle_rad": 1.5707963267948966,
      "angle_param": "fold_angle_rad",
      "direction": "toward_inside"
    }
  ],
  "linework": [
    {
      "role": "cut",
      "closed": false,
      "segments": [
        { "from": { "x": 0, "y": 0 }, "to": { "x": 1, "y": 0 } },
        {
          "kind": "bezier",
          "p0": { "x": 0, "y": 0.5 },
          "p1": { "x": 0.2, "y": 0.1 },
          "p2": { "x": 0.8, "y": 0.9 },
          "p3": { "x": 1, "y": 0.5 }
        }
      ]
    }
  ]
}

判定原则：
- panel 是结构面，不是任意封闭区域。
- panel 的 `name` 必须用稳定、可读的 `snake_case`，方便人工微调。
- fold 是面与面之间的结构铰线，不是所有 score 线。
- linework 是导出刀线，不是几何真值本身。
- 如果一个 panel 不可印刷，accepts_content 设为 false。
- 如果 surface_frame 不确定，可以省略，后续由人工补或让系统自动推导。
- 如果尺寸不确定但比例关系明确，优先输出相对坐标并补 `normalization`。
- 如果某个点位大致正确但控制点不精确，也先输出，允许人工后续微调。
- 如果某条圆弧后续很可能需要非等比缩放，优先改写成 bezier，避免变成椭圆弧后无法直接映射。
- `expr` 先只用简单四则运算和括号；不要输出 `pow`、`sin`、`cos`、指数记法或自定义函数。

现在请根据输入图像输出 JSON。后续我会用本地 Zig 工具把它转成内部 spec。
```

建议补充给模型的上下文：

- 标注图片中的单位和比例
- 指明哪类颜色/线型代表 cut 或 score
- 如果存在多个独立结构，要求它只抽取其中一个
- 默认把 JSON 保存到 `data/json/`，再生成到 `data/spec/`
