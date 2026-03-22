# AI 编写模板

## 推荐路线

这里的 spec 更适合作为 `geo-core` 内部消费层，而不是大模型的首选输出层。更推荐 AI 先产出 JSON，再通过 [template_json_to_spec.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/tools/template_json_to_spec.zig) 生成 spec。

当前这条链路适合：

- 已经识别出 panel 与 fold 关系的结构
- 需要 JSON 中间层再落到内部 spec 的模板
- 带运行时数值参数、select 参数、归一化、arc / bezier 的结构

## Spec schema

根对象字段：

- `key`: 模板 key，例如 `folding_carton.imported_two_panel`
- `label`: 模板名称
- `package_kind`: 当前只支持 `.folding_carton`
- `panels`: panel 列表
- `folds`: fold 列表
- `linework`: 导出线稿列表

### panel

每个 panel 支持：

- `id`
- `boundary`: 闭合线段列表，顺序必须连续
- `surface_frame`: 可选；不填时会按 panel 外接矩形自动生成
- `content_region`: 可选
- `outside_normal`: 可选；默认是 `{ "x": 0, "y": 0, "z": 1 }`
- `accepts_content`: 可选；默认 `true`

### fold

每个 fold 支持：

- `from_panel_id`
- `to_panel_id`
- `from_segment_index`
- `to_segment_index`
- `angle_rad`
- `direction`: `toward_outside` 或 `toward_inside`

### linework

每条 linework 支持：

- `role`: `cut` / `score` / `guide`
- `stroke_style`: 可选；默认按 role 推断
- `closed`: 是否闭合
- `segments`: 线段列表

## 接入方式

1. 先准备一个 JSON 文件，例如 [imported_two_panel.json](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/data/json/imported_two_panel.json)。
2. 用生成器产出 spec，例如 [imported_two_panel_spec.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/data/spec/imported_two_panel_spec.zig)。
3. 新建一个极薄的 Zig wrapper，例如 [imported_two_panel.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/templates/imported_two_panel.zig)。
4. 在 [src/mod.zig](/home/xuyuanmao/workspace/box-design-demo/packages/geo-core/src/mod.zig) 注册。

示例 wrapper：

```zig
const compiled_spec = @import("compiled_spec.zig");
const imported_two_panel_spec = @import("data/spec/imported_two_panel_spec.zig");

const Generated = compiled_spec.defineTemplate(imported_two_panel_spec.spec);

pub const descriptor = Generated.descriptor;
pub const spec = Generated.spec;
pub const Instance = Generated.Instance;
pub const create = Generated.create;
```

## AI 输出要求

如果你已经有稳定的人类或脚本产出的 spec，这一层仍然有价值，因为它是 `geo-core` 内部真正消费的类型化结构。

当前参数 contract 已支持 `numeric_params` 和 `select_params` 两类。前者适合连续数值，后者适合离散结构分支。
