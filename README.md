# Light Stats

一款轻量级的 macOS 状态栏系统监控工具，让你在 3 秒内知道系统当前状态。

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## 特性

- **状态栏常驻** - 随时查看系统状态，无需打开额外窗口
- **信息精准** - CPU、GPU、内存、磁盘、网络、风扇转速一目了然
- **克制设计** - 只读为主，操作极简，不替代活动监视器
- **原生体验** - 纯 Swift + SwiftUI 开发，支持深色/浅色模式

## 截图

状态栏显示：

```
◉  62%  41%  59%  164 GB  ↑7.5 KB/s
   CPU  GPU  MEM  DISK    ↓9.0 KB/s
```

## 功能

### 状态栏监控项

| 项目 | 说明 |
|------|------|
| Logo | 应用图标 |
| CPU | CPU 总使用率 |
| GPU | GPU 利用率 |
| MEM | 内存使用率 |
| DISK | 磁盘可用空间 |
| NET | 实时网络上传/下载速度 |
| FAN | 风扇转速 |

### 概览面板

- **圆环图表** - CPU、GPU、内存使用率可视化
- **系统状态** - 温度、风扇转速、磁盘空间、网络速度
- **核心监控** - 各 CPU 核心使用率详情（可滚动查看）

### 清理释放

- **内存占用排行** - 按内存占用从大到小排列运行中的 App
- **快速关闭** - 悬浮显示关闭按钮，支持温和关闭和强制终止
- **进程合并** - 自动合并多进程应用（如 Electron 应用）

### 设置

- 自定义状态栏显示项（至少保留 1 项）
- 刷新频率：低 / 中 / 高
- 温度单位：℃ / ℉
- 网速单位：KB/s / MB/s

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon 或 Intel 处理器

## 安装

### 从源码构建

1. 克隆仓库：

```bash
git clone https://github.com/EvilIrving/menus-stats.git
cd menus-stats
```

1. 使用 Xcode 打开项目：

```bash
open "Light Stats.xcodeproj"
```

1. 选择目标设备后点击 Run 或按 `Cmd + R` 构建运行

## 技术栈

- **语言**: Swift 5.9+
- **UI**: SwiftUI + AppKit (NSStatusItem)
- **系统接口**:
  - Mach API (CPU 统计)
  - IOKit (GPU、SMC 温度/风扇)
  - NSRunningApplication (进程管理)

## 项目结构

```
Light Stats/
├── Light Stats/
│   ├── AppDelegate.swift      # 应用入口、状态栏和弹出窗口管理
│   ├── SystemMonitor.swift    # 系统监控核心（CPU/GPU/内存/磁盘/网络）
│   ├── AppMemoryManager.swift # 应用内存管理
│   ├── SettingsManager.swift  # 设置管理
│   ├── SettingsView.swift     # 设置界面
│   ├── Assets.xcassets/       # 图标资源
│   └── LightStatsApp.swift    # App 结构定义
└── Light Stats.xcodeproj/      # Xcode 项目配置
```

## 设计理念

> 不是"什么都管"，而是让用户在 3 秒内知道：系统现在正不正常。

- **状态栏优先** - 信息常驻可见
- **统计只读为主** - 展示状态，不修改系统
- **操作极度克制** - 仅提供关闭 App 的能力

## 非目标

- ❌ 不提供自动清理
- ❌ 不修改系统参数
- ❌ 不常驻后台扫描
- ❌ 不替代活动监视器

 