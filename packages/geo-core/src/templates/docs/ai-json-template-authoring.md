# AI 编写模板 JSON

## 推荐路线

如果你的目标是让大模型稳定地产出“模板中间描述”，首选 JSON，而不是直接让它写 Zig。

这里的目标不是要求 AI 一次把所有细节做对，而是让它先完成最繁琐的 70%-90%，然后由人工在 JSON 上做少量修正。

推荐流程：

1. AI 输出 JSON
2. 人工快速检查 panel / fold / linework / 曲线段
3. 运行 [template_json_to_spec.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/tools/template_json_to_spec.zig)
4. 生成 Zig spec 后接入 [compiled_spec.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/compiled_spec.zig)

这样做的好处：

- JSON 更接近大模型的稳定输出区
- 人工更容易审查和局部微调
- Zig 生成器本身还能提供一层类型和语义检查
- 人工微调只改 JSON，不需要直接改 Zig
- `geo-core` 内部仍然保持类型安全的编译期模板定义

## JSON schema

根对象字段：

- `key`
- `label`
- `package_kind`
- `numeric_params`
- `select_params`
- `variables`
- `normalization`
- `panels`
- `folds`
- `linework`

### numeric_params

用于声明运行时可替换的数值参数，例如：

- 物理尺寸：`length`、`width`、`depth`
- fold 角度：`wall_angle_rad`、`lid_angle_rad`
- 结构参数：`lid_length`、`dust_flap_width`

这些参数可以在坐标表达式中直接引用（见下方”参数化坐标表达式”）。

### select_params

用于声明有限枚举选择，例如：

- fold pattern
- lock style
- flap variant

这类参数更适合表达离散结构分支，不应该再硬塞成数字。

### variables

用于定义由 `numeric_params` 和其他 variables 派生的中间变量。变量按声明顺序求值，后面的变量可以引用前面的变量。

```json
"variables": [
  { "name": "y1", "expr": "width" },
  { "name": "y2", "expr": "width + depth" },
  { "name": "y3", "expr": "y2 + lid_length" }
]
```

- `params` = 外部输入（用户可调的物理参数）
- `variables` = 内部派生值（由 params 和其他 variables 计算）
- 坐标/角度表达式可以引用 params 和 variables

变量名不能与 `numeric_params` 的 key 重复。

### normalization

用于把 AI 输出的相对坐标自动映射到实际尺寸。

常见用法：

- AI 输出 `0..1` 或 `0..1000` 的相对坐标
- JSON 中声明 `target_size`
- 运行时通过 `numeric_params` 传入真实宽高

支持字段：

- `source_bounds`
- `target_origin`
- `target_size`
- `flip_y`
- `scale_mode`

### panel

每个 panel 支持：

- `name`
- `boundary`
- `surface_frame`
- `content_region`
- `outside_normal`
- `accepts_content`

`name` 是 AI 输出层的主键，要求：

- 使用稳定、可读的 `snake_case`
- 在同一个模板内唯一
- 生成 Zig spec 时会自动映射成 `enum(u16)` 面板枚举

`boundary` / `content_region` 中的 segment 现在支持三种：

- line: `from` + `to`
- arc: `kind = "arc"` + `center` + `radius` + `start_angle` + `end_angle`
- bezier: `kind = "bezier"` + `p0` + `p1` + `p2` + `p3`

### fold

每个 fold 支持：

- `from_panel`
- `to_panel`
- `from_segment_index`
- `to_segment_index`
- `angle_rad`
- `angle_expr`
- `direction`

如果拓扑固定但开合角度希望在运行时替换，可以保留一个默认 `angle_rad`，再额外声明 `angle_expr`（值为表达式字符串，如 `"wall_angle_rad"`）。

### linework

每条 linework 支持：

- `role`
- `stroke_style`
- `closed`
- `segments`

`segments` 同样支持 `line` / `arc` / `bezier`。

当前边界：

- `arc` 可以正常进入模板系统
- 如果后续还要做非等比归一化，圆弧会变成椭圆弧
- 目前这类情况建议 AI 或人工直接改写成 `bezier`

## 示例

示例 JSON：

- [imported_two_panel.json](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/data/json/imported_two_panel.json)

生成命令：

```bash
bun run gen:geo-template-spec packages/geo-core/src/templates/data/json/imported_two_panel.json
```

如果输入是 `data/json/...`，默认会生成到镜像的 `data/spec/...`。

也可以直接指定整个目录：

```bash
bun run gen:geo-template-spec packages/geo-core/src/templates/data/json
```

这个脚本本身就是 Zig 工具，输入仍然保持 JSON。

当前推荐的协作方式：

1. AI 先输出大体 JSON
2. 人工修 panel 划分、fold 引用、曲线控制点
3. 人工补 `numeric_params` / `select_params` / `normalization`
4. 本地生成 spec 并跑测试

## 参数化坐标表达式

坐标值支持两种写法：

- **数字**：`{"x": 0, "y": 100}` — 常量值（单位 mm）
- **字符串**：`{"x": "length", "y": "width + depth"}` — 引用 `numeric_params` 或 `variables` 的表达式

### 表达式语法

```
expr   = term (('+' | '-') term)*
term   = unary (('*' | '/') unary)*
unary  = '-' unary | atom
atom   = number | identifier | '(' expr ')'
```

支持：`+`、`-`、`*`、`/`、括号、一元负号、数字字面量、标识符（params 或 variables）。

当前不建议扩到函数调用、指数运算或三角函数。对 AI authoring 来说，简单表达式更稳定，也更容易人工审查。像 `pow`、`sin`、`cos`、`exp` 这类能力，只有在模板里出现明确高频需求时才值得加进求值器。

### 示例：使用 variables 定义 mailer box 风格模板

```json
{
  "numeric_params": [
    { "key": "length", "label": "Length", "default_value": 95 },
    { "key": "width", "label": "Width", "default_value": 78 },
    { "key": "depth", "label": "Depth", "default_value": 28 },
    { "key": "lid_length", "label": "Lid Length", "default_value": 52 }
  ],
  "variables": [
    { "name": "y1", "expr": "width" },
    { "name": "y2", "expr": "width + depth" },
    { "name": "y3", "expr": "y2 + lid_length" }
  ],
  "panels": [
    {
      "name": "front",
      "boundary": [
        { "from": { "x": 0, "y": 0 },          "to": { "x": "length", "y": 0 } },
        { "from": { "x": "length", "y": 0 },    "to": { "x": "length", "y": "y1" } },
        { "from": { "x": "length", "y": "y1" }, "to": { "x": 0, "y": "y1" } },
        { "from": { "x": 0, "y": "y1" },        "to": { "x": 0, "y": 0 } }
      ]
    },
    {
      "name": "side",
      "boundary": [
        { "from": { "x": 0, "y": "y1" },         "to": { "x": "length", "y": "y1" } },
        { "from": { "x": "length", "y": "y1" },   "to": { "x": "length", "y": "y2" } },
        { "from": { "x": "length", "y": "y2" },   "to": { "x": 0, "y": "y2" } },
        { "from": { "x": 0, "y": "y2" },          "to": { "x": 0, "y": "y1" } }
      ]
    },
    {
      "name": "lid",
      "boundary": [
        { "from": { "x": 0, "y": "y2" },         "to": { "x": "length", "y": "y2" } },
        { "from": { "x": "length", "y": "y2" },   "to": { "x": "length", "y": "y3" } },
        { "from": { "x": "length", "y": "y3" },   "to": { "x": 0, "y": "y3" } },
        { "from": { "x": 0, "y": "y3" },          "to": { "x": 0, "y": "y2" } }
      ]
    }
  ],
  "folds": [
    {
      "from_panel": "front",
      "to_panel": "side",
      "from_segment_index": 1,
      "to_segment_index": 3,
      "angle_rad": 1.5707963267948966,
      "angle_expr": "depth"
    }
  ]
}
```

`radius`、`start_angle`、`end_angle` 同样支持表达式。

### 何时用表达式 vs normalization

| 场景 | 推荐方式 |
|------|---------|
| 纸盒类（坐标由 length/width/depth 决定） | **参数化表达式**，不需要 normalization |
| AI 输出相对坐标（0..1 范围） | **normalization**，配合 `target_size` |
| 混合场景 | 表达式优先；normalization 可选 |

### 编译期验证

表达式中引用的所有标识符会在编译期被检查是否存在于 `numeric_params` 或 `variables`。拼写错误会产生编译错误。变量表达式只能引用 params 和声明顺序在前面的 variables。

## 推荐给 AI 的要求

- 只输出 JSON
- 不输出解释
- `boundary` 必须连续闭合
- fold 只引用真实铰线
- linework 不能省略
- 如果能判断出圆弧或贝塞尔，就直接输出 `arc` / `bezier`
- **优先使用 variables 定义关键坐标**（如 `y2 = width + depth`），然后在坐标中引用变量名
- 用参数化表达式让坐标语义清晰
- 如果坐标更适合相对表达，输出相对坐标并配合 `normalization`
- 不确定的线先标成 `guide`，不要瞎猜结构关系
