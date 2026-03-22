# `wrench` 使用指南

`[wrench.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/wrench.zig)` 是手工模板最常用的一层脚手架。它解决的是“重复样板代码”，不是模板语义本身。

适合用 `wrench` 的场景：

- 矩形 panel
- 连续 strip
- 常见 fold/hinge 关系
- 规则圆弧、圆角 flap

不适合直接靠 `wrench` 硬拼的场景：

- 拓扑很不规则的结构
- 需要显式自定义每段边界语义
- AI 导入后还要大量逐段修正的模板

## 常见用法

### 1. 解析数值参数

- `resolveNumericParam(...)`
- `resolveSelectParam(...)`

适合模板内把 `numeric_params` / `select_params` 映射成具体几何分支。

### 2. 构造矩形 panel

- `rectSegments(...)`
- `initRectPanel(...)`
- `initRectPanelSet(...)`
- `initRectPanelWithContentInset(...)`

如果结构是若干独立矩形面，优先从这里开始。

### 3. 构造连续 strip

- `initRectPanelStrip(...)`
- `scoreSegmentsForStrip(...)`
- `foldChainRightToLeft(...)`

适合 tube carton、连续侧板、简单链式面板。

### 4. 构造 linework

- `cutPath(...)`
- `bleedPath(...)`
- `safePath(...)`
- `foldPath(...)`
- `appendCutLinework(...)`
- `appendScoreLinework(...)`

这里要注意：

- `appendCutLinework(...)` 适合“每个 panel 的边界都确实要单独导出”为 cut path 的情况
- 如果真实刀线应该是“一个整体外轮廓 + 内部 fold”，不要机械地把每个 panel 都 append 成 cut
- `four_panel_tube` 这类 strip，更适合手工组一个 outer cut path，再单独 append fold
- 当前推荐线型语义：
- `cut`：切刀线，实线，蓝色
- `bleed`：出血线，实线，红色
- `safe`：安全线，虚线，灰色
- `fold`：折叠线，虚线，蓝色
- `scorePath(...)` 仍然保留为兼容旧模板的别名，内部等价于 `foldPath(...)`

### 5. 构造曲线 panel

- `arcSegment(...)`
- `annularSectorSegments(...)`
- `roundedFlapSegments(...)`
- `initPanelBySegments(...)`

适合扇形 panel、圆角 flap、带 arc 的边界。

## 推荐组合

### 简单双面

- `initRectPanel(...)`
- `fold(...)`
- `cutPath(...)`
- `foldPath(...)`

### 连续 strip

- `initRectPanelStrip(...)`
- `scoreSegmentsForStrip(...)`
- `foldChainRightToLeft(...)`
- 手工决定 cut line 是整体轮廓还是逐 panel 导出

### 自定义曲线面

- `annularSectorSegments(...)` 或自己拼 segments
- `initPanelBySegments(...)`
- 再手工补 linework / fold

## 经验规则

- `wrench` 用来降样板，不用来代替几何判断
- panel / fold / linework 的语义先想清楚，再选 helper
- `geo-core` 的几何坐标默认按物理毫米处理；模板里的 `length/width/depth/x/y/radius` 如果没有额外声明，都应理解为 mm
- 如果你开始为了适配 helper 去扭曲模板结构，说明该回到手写 segments 了
