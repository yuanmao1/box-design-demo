# Template Guide

这份文档说明 `packages/geo-core/src/templates` 中新增模板的基本方法、几何设计规则和测试要求。

## 目标

模板层的职责不是做前端适配，也不是重复实现 package 层算法。模板层只负责：

- 定义业务参数
- 把业务参数映射到几何真值
- 构造稳定的 `Panel` / `Fold` / `StyledPath2D`
- 接入模板注册表

模板产出的真值会继续被 `package.zig` 用来做：

- 2D 刀线导出
- 3D 折叠预览
- 内容区域校验

## 一个模板必须包含什么

每个模板文件应至少包含：

- `descriptor`
- `Instance`
- `PanelKey`
- `create(...)`
- 至少一个针对模板行为的测试

典型结构参考：

- [simple_two_panel.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/simple_two_panel.zig)
- [mailer_box.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/mailer_box.zig)

建议每个模板都定义本地 `PanelKey` 枚举，并通过一个小的 `panelId(...)` helper 转成 `types.PanelId`。这样 fold、content、测试都可以按结构语义引用 panel，而不是直接写裸数字。

常用模板辅助函数在 [wrench.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/wrench.zig)：

- `resolveNumericParam(...)`
- `rectSegments(...)`
- `closedPath(...)`
- `openPath(...)`
- `cutPath(...)`
- `scorePath(...)`
- `lineSegment(...)`
- `scoreLine(...)`
- `initRectPanel(...)`
- `initRectPanelWithContentInset(...)`
- `fold(...)`
- `initRectPanelStrip(...)`
- `scoreSegmentsForStrip(...)`
- `foldChainRightToLeft(...)`
- `appendCutLinework(...)`
- `appendScoreLinework(...)`
- `arcSegment(...)`
- `annularSectorSegments(...)`
- `roundedFlapSegments(...)`
- `initPanelBySegments(...)`

## 推荐开发步骤

1. 先确定业务参数
2. 把参数映射成明确几何数值
3. 生成 panel 边界和 surface frame
4. 定义 fold 轴和 fold direction
5. 生成 linework
6. 构造 `FoldingCartonModel`
7. 注册到 [mod.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/mod.zig)
8. 补测试

如果模板里出现大量重复的：

- `types.Path2D.baseBy(&segments)`
- `StyledPath2D{ ... }`
- `Fold{ ... }`
- 矩形 panel 的 `withSurfaceBy(...)`

优先考虑先复用或补充 `wrench.zig`，而不是把样板代码复制到每个模板。

当前建议优先复用的脚手架模式：

- 连续一排矩形面：`initRectPanelStrip(...)`
- 连续面之间的 score 线：`scoreSegmentsForStrip(...)`
- 沿 strip 相邻连接的 fold：`foldChainRightToLeft(...)`
- 批量导出 cut/score linework：`appendCutLinework(...)` / `appendScoreLinework(...)`

这几个 helper 适合：

- tube carton
- mailer 主体板片
- tuck end 主体链
- 任何“矩形 strip + 相邻 hinge”结构

面向曲线面/圆角 flap 的 helper 适合：

- 扇形 panel
- 圆角 flap
- 带圆弧边界的 lock/tab 面
- 任何“显式 segment + surface_frame”的非矩形 panel

## 参数设计规则

参数应该表达业务含义，而不是泄漏内部实现细节。

优先使用：

- `length`
- `width`
- `depth`
- `panel_height`
- `lid_length`
- `open_ratio`
- `safe_margin`

不要优先暴露：

- “第 3 个 panel 的第 2 条边旋转角度”
- 只对当前实现有意义的临时量

如果需要状态型参数，比如：

- 半开合
- erected / flat / semi_open

应先在模板内把它们映射成具体 fold angle，再构造几何真值。

## 几何真值规则

模板必须明确产出这些对象：

- `Panel`
- `Fold`
- `StyledPath2D`

其中关键要求如下。

### 1. Panel

每个 `Panel` 至少要定义：

- `boundary`
- `surface_frame`
- 必要时 `content_region`

规则：

- `boundary` 是面真实边界
- `surface_frame` 是稳定的面局部坐标系，不要把它当纯渲染 hint
- 如果可印刷区域小于边界，必须显式给 `content_region`
- `accepts_content = false` 只用于明确不可放内容的 flap / glue / lock 区

### 2. Fold

每个 `Fold` 至少要定义：

- `from_panel_id`
- `to_panel_id`
- `axis.from_edge`
- `axis.to_edge`
- `angle_rad`
- `direction`

规则：

- `from_edge` 和 `to_edge` 必须是同一条 hinge 的两侧引用
- edge 必须共线且覆盖同一铰线
- `angle_rad` 表示折叠量值
- `direction` 表示折向：
  - `toward_outside`
  - `toward_inside`

不要再靠手工给 `angle_rad` 写正负号来表达折向。

### 3. Linework

`linework` 只表达导出线稿，不是几何真值的来源。

规则：

- cut line 用 `.role = .cut`
- score line 用 `.role = .score`
- 不要让前端靠 linework 反推 fold 关系

## 如何判断一个模板还能不能继续用 FoldingCartonModel

如果模板最终能稳定表达成：

- 若干 panel
- 若干 fold
- 若干 linework
- 若干 content region

那么优先继续用 `FoldingCartonModel`。

例如：

- tube carton
- tuck end carton
- mailer box
- flap 结构
- 带 Arc 边界的 panel

如果模板本质上不是 panel/fold 拓扑，而是连续曲面或壳体，才考虑新增 model。

例如：

- 圆锥包裹面
- 软袋壳体
- 真正的连续曲面结构

## Root panel 设计建议

模板应优先选“结构基准面”作为 root。

通常建议：

- 盒型：底面作为 root
- 信封/单片：主面作为 root
- 带盖结构：盒体基准面作为 root，不要把 lid 当 root

原因：

- root 应该是装配基准
- root 不应该随着开合状态频繁变化

注意：

- root 的选择是拓扑问题
- “模型在 3D 场景里朝上还是朝侧面”通常是前端世界坐标适配问题，不是模板 root 问题

## Fold direction 设计建议

如果你要的是“盒子开口朝上”，通常应该：

- 底面作为 root
- 侧壁相对底面 `toward_outside`
- lid / dust flap / lock flap 再根据结构语义定义为 `toward_inside` 或 `toward_outside`

不要凭视觉猜测正负号。应按结构语义声明 `direction`，让 package 层去推导 signed rotation。

## 曲线面和非矩形面

模板可以使用：

- `Line`
- `Arc`
- `Bezier`

适用场景：

- 扇形面
- 圆角 flap
- 非矩形锁扣边

规则：

- `surface_frame` 仍需显式稳定
- 非矩形 panel 必须重点测试内容放置
- 如果 `boundary` 和 `content_region` 不同，两者都要定义

## 注册模板

新增模板后必须同步修改 [mod.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/mod.zig)：

- 在 `folding_carton` namespace 中 `@import`
- 在 `TemplateInstance` 中加分支
- 在 `exportTemplates()` 中导出 descriptor
- 在 `createTemplate(...)` 中注册 key -> create

否则 wasm 和前端都无法发现新模板。

## 测试要求

每个模板至少应覆盖这些场景中的一部分：

- 能生成预期 panel/fold/linework 数量
- `buildPreview3D` 成功
- 关键 fold 的角度量值正确
- 至少一个合法内容通过
- 至少一个非法内容失败

复杂模板还应补：

- flap / lid 的方向测试
- `accepts_content = false` 测试
- `content_region != boundary` 测试
- 曲线边界内容越界测试

## 常见错误

### 1. 只画了 linework，没有定义 panel/fold

这会让 2D 看起来正常，但 3D 和内容校验没有真值可用。

### 2. 用 `angle_rad` 正负号表达折向

现在应该使用 `direction`。

### 3. `surface_frame` 只是随便填一个包围盒

对于复杂面，这会导致内容投影错误。

### 4. content 允许区没有单独建模

如果模板存在安全边距、锁扣区、糊盒区，应该用 `content_region` 表达。

### 5. 把前端显示习惯写进模板几何

模板负责几何真值；前端负责相机、世界坐标、显示朝向。

## 最小检查清单

在提交模板前，至少确认：

- key 稳定且有业务意义
- 参数名不是内部实现细节
- panel/fold/linework 都已构造
- fold 的 `direction` 已声明
- root panel 选的是结构基准面
- 已注册到 `mod.zig`
- 已补 Zig 测试
- `zig build test` 通过
