# Plan: Menu Stats MVP

## 目标

实现 macOS 状态栏系统监控工具的 MVP 版本，覆盖 PRD 中定义的核心功能。

## 里程碑

### M1: 基础架构 (task001-003)
- 状态栏 App 框架
- NSStatusItem 基础设置
- Popover 容器

### M2: 系统数据采集 (task004-008)
- CPU 使用率（总体 + 单核）
- GPU 利用率
- 内存统计
- 磁盘/网络/风扇

### M3: 概览 Tab (task009-011)
- 圆环饼图（CPU/GPU/MEM）
- 系统状态区（温度/风扇/磁盘/网络）
- 核心使用率列表

### M4: 清理释放 Tab (task012-014)
- 用户 App 列表
- 内存占用显示
- 关闭 App 功能

### M5: 设置页面 (task015-016)
- 状态栏显示设置
- 刷新频率/单位设置

## 技术约束

- Swift / SwiftUI + AppKit
- macOS 14+ (Sonoma)
- Mach API / IOKit / NSRunningApplication

## 风险

- GPU/温度数据在某些设备可能不可用，需优雅降级
- 关闭 App 权限可能受限
