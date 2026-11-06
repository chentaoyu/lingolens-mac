# LingoLens 品牌标志

## 概念

**对话镜头（Conversation Lens）**：一个圆环代表「镜头」，左下角伸出的尾巴让它同时是一个**对话气泡**，
圆环内的两行短横是**两行字幕 / 译文**。三层含义对应产品三件事：看文字（翻译）、听对话（字幕）、记内容（纪要）。

- 形状语言：单一圆环 + 一个尾巴 + 两条短线，只有 4 个元素，16px 下仍然可辨。
- 颜色：延续原型的品牌主色靛蓝，渐变 `#5C63E8 → #3338A6`；白色标志保证在深色 Dock 和浅色 Finder 都清晰。
- 无内置阴影、无文字：交给系统渲染，避免在浅色背景上出现脏边。

## 文件

| 文件 | 用途 |
|---|---|
| `icon-1024.png` | 源文件（AppIcon 由它缩放生成） |
| `mark-1024.png` | 透明背景标志，用于需要单色的场合 |
| `preview-small.png` | 16 / 32 / 64 / 128 实际像素的 3 倍放大检查图 |
| `make-icon.swift` | 生成脚本：`swiftc -O make-icon.swift -o render && ./render` |

## 落地位置

- `App/Assets.xcassets/AppIcon.appiconset`：macOS 16–512@2x 全尺寸。
- `App/Assets.xcassets/BrandIcon.imageset`：侧边栏 20pt 与引导页 74pt 使用的同一图形。
- `project.yml`：`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`。

## 设计约束

- 圆角比例 22.37%（macOS squircle 近似），图标本体占画布 824/1024，四周留白给系统摆放。
- 标志占本体宽度约 62%，在 32px 下线条仍不糊。
- 主色与 App 内的 `AccentColor` 同源，避免应用内外的品牌割裂。
