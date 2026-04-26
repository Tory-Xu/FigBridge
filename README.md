# FigBridge

macOS 原生 `SwiftUI` Figma YAML 工作台，采用 `MVVM` 架构。

当前仓库已实现首版工程骨架与核心链路：

- `生成` 页：解析多行 Figma `design` 链接、检测 `claude` / `codex`、顺序或并发生成 YAML
- `查看` 页：扫描批次目录、查看 YAML、导出 zip、从 zip 导入批次
- `设置` 页：保存 Figma Token、默认 Prompt、默认输出目录、默认生成模式和并发数
- `Figma REST API`：节点元数据、节点预览图、图片资源解析与本地缓存

## 工程结构

- `Sources/FigBridgeCore`
  - 领域模型
  - 链接解析
  - Agent 检测/执行
  - Figma REST API 服务
  - 批次存储与导入导出
  - 生成协调器
- `Sources/FigBridgeApp`
  - SwiftUI App 入口
  - 三页视图
  - ViewModel

## 运行

```bash
swift run FigBridge
```

## 测试

```bash
swift test
```

## 打包 DMG

```bash
./scripts/package-dmg.sh
```

产物输出到 `dist/FigBridge.dmg`，脚本会先执行 `swift build -c release`，再组装 `FigBridge.app` 并打包为 `dmg`。

## 当前已实现的关键行为

- 支持解析：
  - `@url`
  - `描述: @url`
  - 多行混合输入
- 以 `fileKey + nodeId` 去重
- 节点 `node-id` 自动标准化为 `2522:8028`
- 启动时检测本机 `claude` / `codex`
- 选中生成条目时懒加载 Figma 预览和资源
- 批次目录写入 `batch.json`、`meta.json`、`source-input.txt`
- 支持目录导入、zip 导出、zip 导入

## 当前未完成

- 查看页的批次删除、目录打开
- 系统文件选择器接入
- 节点 `PNG/SVG` 单独导出按钮
- 生成过程取消、中断恢复、进度展示
- 更完整的 Figma 节点遍历和资源分类
- `.xcodeproj` 工程文件
