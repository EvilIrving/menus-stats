# macOS 状态栏系统监控工具 PRD

## 一、背景与目标

### 1. 背景

macOS 自带的「活动监视器」功能强大，但存在以下问题：

- 必须打开独立窗口，无法常驻可见
- 信息密度高但获取路径长，不适合频繁查看
- 普通用户很少真正理解 CPU / 内存 / GPU 的实时状态

大量第三方用户真实需求集中在：

- **随时知道系统是否“忙”**
- **快速定位内存被谁占用**
- **在必要时快速释放资源**

### 2. 产品目标

打造一个：

- 常驻 macOS 状态栏
- 信息准确、展示克制
- 不替代活动监视器，但覆盖 80% 高频需求

关键词：**快速感知 · 只读为主 · 克制操作**。

---

## 二、整体产品结构

### 1. 核心形态

- 类型：macOS 状态栏 App
- 常驻状态栏，一个图标 + 若干状态文本
- 点击状态栏，弹出 Popover
- 点击屏幕其他地方或者默认 10s 后关闭

### 2. 核心页面

```
状态栏
  ↓ 点击
Popover
 ├── 概览 Tab
 └── 清理释放 Tab
```

---

## 三、状态栏设计

### 1. 状态栏内容

- 仅一个 `NSStatusItem`
- 顺序固定，不允许用户调整

固定顺序如下：

```
Logo / CPU / GPU / MEM / DISK / NET / FAN
```

### 2. 双行显示布局

每个监控项采用上下双行结构：

- **上方**：显示数值（如 `62%`、`99 GB`），使用较小字号（9pt 等宽数字字体）
- **下方**：显示文字标签（如 `CPU`、`DISK`），字号更小（7pt），颜色为次要色

**网络项特殊处理**：

- 上方显示上传速度（如 `↑7.5 KB/s`）
- 下方显示下载速度（如 `↓7.5 KB/s`）
- 上下两行使用相同字号（9pt 等宽数字字体），间距更紧凑

**风扇转速**:

状态栏不显示具体的转速，设计一个模拟风扇旋转的效果。转速越高，风扇转速越快。为了降低风扇太快，需限制模拟风扇的最大转速。

### 3. 固定宽度格子

为避免数值变化导致界面抖动，每种监控项使用固定宽度：

| 项目 | 宽度 | 示例内容 |
|------|------|----------|
| Logo | 18pt | ◉ |
| CPU | 32pt | 99% |
| GPU | 32pt | 41% |
| MEM | 32pt | 59% |
| DISK | 48pt | 999 GB（向上取整） |
| NET | 70pt | ↑99.9 MB/s / ↓99.9 MB/s |
| FAN | 58pt | 9999 RPM |
| 分隔间距 | 8pt | - |

技术要点：

- 使用 `monospacedDigitSystemFont` 确保数字等宽
- 每个格子内文字居中对齐
- 总宽度根据启用项目动态计算

### 4. 显示规则

- 每一项支持「是否显示」开关
- **至少需要选中 1 项**
- 当用户尝试全部关闭时：
  - 自动保留 CPU 项
  - 提示：
    > “状态栏至少需要显示一个系统状态”

---

## 四、Popover 设计

Popover 仅包含两个 Tab，避免复杂导航。

```
┌──────── Popover ────────┐
│  概览 | 清理释放        │
├────────────────────────┤
│  内容区                │
└────────────────────────┘
```
 
 
 
## 七、设置页面

### 1. 状态栏显示设置

Checkbox 列表：

- Logo
- CPU
- GPU
- MEM
- Disk
- Net
- Fan

规则：

- 至少一个必须勾选
- 全部取消时自动恢复 CPU

---

### 2. 其他设置

- 刷新频率：低 / 中 / 高
- 温度单位：℃ / ℉
- 网速单位：KB/s / MB/s

---

## 八、技术选型

### 1. 技术栈

- 语言：Swift
- UI：SwiftUI + AppKit（NSStatusItem）
- 最低系统版本：macOS 14 (Sonoma)
  - 支持最近 3 个主要版本（macOS 14/15/26）可覆盖约 90% 的活跃用户
- 系统接口：
  - Mach API
  - IOKit
  - NSRunningApplication

---

## 九、核心算法说明（伪代码）

### 1. CPU 使用率（Mach）

```pseudo
prev = read_cpu_ticks()
sleep(1s)
now = read_cpu_ticks()
delta = now - prev
cpu_usage = (user + system) / total
```

---

### 2. 单核 CPU

```pseudo
cores = host_processor_info()
for core in cores:
  usage = (user + system) / total
```

---

### 3. GPU 利用率（IOKit）

```pseudo
service = find IOAccelerator
stats = service["PerformanceStatistics"]
util = stats["Device Utilization %"]
```

---

### 4. 内存统计

```pseudo
vm = host_vm_info()
used = active + wired + compressed
percent = used / total
```

---

### 5. App 内存占用

```pseudo
for app in runningApplications:
  task = task_for_pid(app.pid)
  mem = task.resident_size
```

---

## 十、用户友好提示（UX 文案）

### 1. 关闭 App 按钮悬浮提示
>
> “关闭应用前请确认已保存数据，强制关闭可能导致数据丢失。”

### 2. 全部取消状态栏显示
>
> “状态栏至少需要显示一个系统状态。”

### 3. GPU / 温度不可用
>
> “当前设备暂不支持该项数据获取。”

---

## 十一、非目标（明确不做）

- 不提供自动清理
- 不修改系统参数
- 不常驻后台扫描高频数据
- 不替代活动监视器

---

## 十二、总结

本产品是一个：

- **状态栏优先**
- **统计只读为主**
- **操作极度克制**

的 macOS 系统监控工具。

目标不是“什么都管”，而是**让用户在 3 秒内知道：系统现在正不正常**。

---

## 十三、开发验证

- 无须自动化验证构建和运行
- 用户自行在 Xcode 中构建并测试

---

## 十四、实现状态追踪

> 最后更新：2024-12-25

### 1. 状态栏

| 功能 | 状态 | 说明 |
|------|------|------|
| NSStatusItem 基础框架 | ✅ 已完成 | `AppDelegate.swift` |
| 双行显示布局（值+标签） | ✅ 已完成 | `StatusBarView` |
| Logo 显示 | ✅ 已完成 | 支持自定义图标 |
| CPU 使用率显示 | ✅ 已完成 | 百分比格式 |
| GPU 利用率显示 | ✅ 已完成 | 不可用时显示 N/A |
| MEM 内存显示 | ✅ 已完成 | 百分比格式 |
| DISK 磁盘显示 | ✅ 已完成 | 向上取整 GB |
| NET 网络显示 | ✅ 已完成 | 上传/下载双行 |
| FAN 风扇显示 | ✅ 已完成 | RPM 数值显示 |
| 风扇旋转动画效果 | ❌ 未实现 | PRD 描述的模拟转动效果 |
| 固定宽度格子 | ✅ 已完成 | 防止数值抖动 |
| 显示项开关 | ✅ 已完成 | 支持用户自定义 |
| 至少一项验证 | ✅ 已完成 | 取消全部时自动保留 CPU |

### 2. Popover 弹窗

| 功能 | 状态 | 说明 |
|------|------|------|
| Popover 基础框架 | ✅ 已完成 | `.transient` 行为 |
| 双 Tab 结构（概览/清理释放） | ✅ 已完成 | - |
| 设置按钮入口 | ✅ 已完成 | 右上角齿轮图标 |
| 10 秒自动关闭 | ❌ 未实现 | 当前仅点击外部关闭 |

### 3. 概览 Tab

| 功能 | 状态 | 说明 |
|------|------|------|
| 圆环饼图（CPU/GPU/MEM） | ✅ 已完成 | `RingView` |
| CPU 悬浮显示 System/User | ✅ 已完成 | `.help()` 修饰符 |
| 温度显示 | ✅ 已完成 | SMC 读取，支持 ℃/℉ |
| 风扇转速显示 | ✅ 已完成 | SMC 读取 |
| 磁盘空间显示 | ✅ 已完成 | 可用/总量 |
| 网络速度显示 | ✅ 已完成 | 实时上传/下载 |
| 核心使用率列表 | ✅ 已完成 | 进度条 + 颜色渐变 |

### 4. 清理释放 Tab

| 功能 | 状态 | 说明 |
|------|------|------|
| 内存摘要区 | ✅ 已完成 | 进度条 + 颜色 |
| 运行中 App 计数 | ✅ 已完成 | - |
| 用户 App 列表 | ✅ 已完成 | 仅 regular apps |
| 状态栏 App 列表 | ⚠️ 部分 | 代码中已注释，待启用 |
| 进程合并显示 | ✅ 已完成 | 进程树追溯 |
| 按内存排序 | ✅ 已完成 | 降序 |
| 悬浮显示关闭按钮 | ✅ 已完成 | 右推滑出动画 |
| 关闭按钮 Tooltip | ✅ 已完成 | `.help()` 修饰符 |
| 正常关闭 | ✅ 已完成 | `terminate()` |
| 强制关闭弹窗 | ✅ 已完成 | Alert 二次确认 |
| 多进程关闭处理 | ✅ 已完成 | 先主进程后子进程 |

### 5. 设置页面

| 功能 | 状态 | 说明 |
|------|------|------|
| 状态栏显示开关（7项） | ✅ 已完成 | Checkbox 列表 |
| 刷新频率设置 | ✅ 已完成 | 低/中/高 |
| 温度单位设置 | ✅ 已完成 | ℃/℉ |
| 网速单位设置 | ✅ 已完成 | 自动/KB/s/MB/s |

### 6. 技术实现

| 功能 | 状态 | 说明 |
|------|------|------|
| CPU 使用率（Mach API） | ✅ 已完成 | `CPUInfo` |
| 单核 CPU 使用率 | ✅ 已完成 | `host_processor_info` |
| GPU 利用率（IOKit） | ✅ 已完成 | `GPUInfo` |
| 内存统计（vm_statistics64） | ✅ 已完成 | `MemoryInfo` |
| 磁盘信息（FileManager） | ✅ 已完成 | `DiskInfo` |
| 网络速度（getifaddrs） | ✅ 已完成 | `NetworkInfo` |
| 温度/风扇（SMC） | ✅ 已完成 | `SMCInfo` |
| App 内存（task_for_pid） | ✅ 已完成 | `AppMemoryManager` |
| 进程树构建（ppid） | ✅ 已完成 | `AppMemoryManager` |
| UserDefaults 持久化 | ✅ 已完成 | `SettingsManager` |

### 7. 代码文件结构

```
Light Stats/Light Stats/
├── menu_statsApp.swift      # App 入口
├── AppDelegate.swift        # 状态栏管理 + Popover UI
├── SystemMonitor.swift      # 系统监控核心逻辑
├── AppMemoryManager.swift   # App 内存管理
├── SettingsManager.swift    # 用户设置管理
├── SettingsView.swift       # 设置页面 UI
└── Assets.xcassets/         # 资源文件
```

---

## 开源实现

https://github.com/exelban/stats