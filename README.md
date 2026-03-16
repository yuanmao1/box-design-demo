# Box Design Demo

一个基于 Bun + Zig 的包装结构设计工作区。

仓库分为三层：

- `packages/geo-core`
  - 几何真值、模板参数、2D 刀线、3D 预览节点、wasm 导出
- `apps/frontend`
  - Studio 前端，消费 `geo-core.wasm`
- `apps/backend`
  - 后端服务层

## Requirements

- Bun
- Zig

## Install

```bash
bun install
```

## Development

先构建 wasm，并自动复制到前端静态目录：

```bash
bun run build:wasm
```

启动前端：

```bash
bun run dev:frontend
```

启动后端：

```bash
bun run dev:backend
```

## Common Commands

构建 wasm 并复制到 `apps/frontend/public/geo-core.wasm`：

```bash
bun run build:wasm
```

运行 `geo-core` 测试：

```bash
bun run test:geo-core
```

运行前端测试：

```bash
bun run test:frontend
```

运行前端类型检查：

```bash
bun run check:frontend
```

构建前端：

```bash
bun run build:frontend
```

## Notes

- 前端默认从 `/geo-core.wasm` 加载 wasm，所以每次修改 `packages/geo-core` 导出边界后，都应该重新运行 `bun run build:wasm`。
- 如果改动了 `geo-core` 的输出 schema，前端类型和消费逻辑需要同步更新。
