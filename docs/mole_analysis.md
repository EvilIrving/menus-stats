# Mole 系统监控技术分析文档

## 1. 项目概述

**Mole** 是一个用 Go 语言编写的 macOS 系统监控与清理工具，主要特性包括：
- 实时系统状态监控（`mo status` 命令）
- 深度系统清理
- 应用卸载
- 磁盘分析

本文档重点分析其**系统监控**功能的技术实现。

---

## 2. 技术栈

| 组件 | 技术/库 | 用途 |
|------|---------|------|
| 语言 | Go 1.24+ | 核心开发语言 |
| TUI 框架 | [Bubble Tea](https://github.com/charmbracelet/bubbletea) | 终端 UI 框架（Elm 架构） |
| 样式 | [Lip Gloss](https://github.com/charmbracelet/lipgloss) | 终端样式渲染 |
| 系统指标 | [gopsutil](https://github.com/shirou/gopsutil/v3) | 跨平台系统指标采集 |
| 并发 | `golang.org/x/sync` | 并发控制 |

---

## 3. 架构设计

### 3.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                      main.go (入口)                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Bubble Tea Model (MVC)                     │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐  │ │
│  │  │  Init()  │  │ Update() │  │       View()         │  │ │
│  │  └────┬─────┘  └────┬─────┘  └──────────┬───────────┘  │ │
│  └───────┼─────────────┼───────────────────┼──────────────┘ │
│          │             │                   │                 │
│  ┌───────▼─────────────▼───────────────────▼──────────────┐ │
│  │                    Collector                           │ │
│  │  (metrics.go - 并发指标收集器)                          │ │
│  └───────────────────────┬────────────────────────────────┘ │
│                          │                                   │
│  ┌───────────────────────▼────────────────────────────────┐ │
│  │              各模块 Metrics 采集器                       │ │
│  │  ┌──────┐ ┌────────┐ ┌──────┐ ┌─────────┐ ┌─────────┐ │ │
│  │  │ CPU  │ │ Memory │ │ Disk │ │ Battery │ │ Network │ │ │
│  │  └──────┘ └────────┘ └──────┘ └─────────┘ └─────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 核心数据结构

```go
// 指标快照 - 包含所有监控数据
type MetricsSnapshot struct {
    CollectedAt    time.Time       // 采集时间
    Host           string          // 主机名
    Platform       string          // 平台版本
    HealthScore    int             // 健康分数 0-100
    HealthScoreMsg string          // 健康状态消息
    CPU            CPUStatus       // CPU 状态
    GPU            []GPUStatus     // GPU 状态
    Memory         MemoryStatus    // 内存状态
    Disks          []DiskStatus    // 磁盘状态
    DiskIO         DiskIOStatus    // 磁盘 IO
    Network        []NetworkStatus // 网络状态
    Proxy          ProxyStatus     // 代理状态
    Batteries      []BatteryStatus // 电池状态
    Thermal        ThermalStatus   // 温度状态
    TopProcesses   []ProcessInfo   // 进程列表
    ...
}
```

---

## 4. 核心功能实现详解

### 4.1 内存监控 (metrics_memory.go)

**你关注的显示效果：**
```
Free   ████░░░░░░░░░░░░   26.2%
4.2 GB available
Swap   ██████████████░░   89.0% (4.5G/5.0G)
```

#### 技术实现：

```go
type MemoryStatus struct {
    Used        uint64   // 已使用内存
    Total       uint64   // 总内存
    UsedPercent float64  // 使用百分比
    SwapUsed    uint64   // Swap 已使用
    SwapTotal   uint64   // Swap 总量
    Cached      uint64   // 文件缓存
    Pressure    string   // 内存压力: normal/warn/critical
}
```

**数据采集方式：**

| 指标 | 采集方式 | 说明 |
|------|----------|------|
| 基础内存 | `gopsutil/mem.VirtualMemory()` | 跨平台 API |
| Swap | `gopsutil/mem.SwapMemory()` | 交换内存 |
| 文件缓存 | `vm_stat` 命令解析 | macOS 特有，解析 "File-backed pages" |
| 内存压力 | `memory_pressure` 命令 | macOS 特有，返回 normal/warn/critical |

**关键代码：**
```go
func collectMemory() (MemoryStatus, error) {
    vm, _ := mem.VirtualMemory()  // gopsutil 库
    swap, _ := mem.SwapMemory()
    pressure := getMemoryPressure()  // 调用 memory_pressure 命令
    
    // macOS 特殊处理：vm.Cached 为 0，需从 vm_stat 获取
    cached := vm.Cached
    if runtime.GOOS == "darwin" && cached == 0 {
        cached = getFileBackedMemory()  // 解析 vm_stat 输出
    }
    ...
}
```

---

### 4.2 磁盘监控 (metrics_disk.go)

**你关注的显示效果：**
```
INTR   ██████████░░░░░░   63.8% (294G/460G)
EXTR1  ███████████████░   97.4% (16G/16G)
EXTR2  ███████████████░   97.0% (8G/8G)
Read   ▯▯▯▯▯  0.0 MB/s
Write  ▯▯▯▯▯  0.0 MB/s
```

#### 技术实现：

```go
type DiskStatus struct {
    Mount       string   // 挂载点
    Device      string   // 设备名
    Used        uint64   // 已使用
    Total       uint64   // 总容量
    UsedPercent float64  // 使用百分比
    External    bool     // 是否外置磁盘
}

type DiskIOStatus struct {
    ReadRate  float64  // 读取速率 MB/s
    WriteRate float64  // 写入速率 MB/s
}
```

**数据采集方式：**

| 指标 | 采集方式 | 说明 |
|------|----------|------|
| 分区列表 | `gopsutil/disk.Partitions()` | 获取所有分区 |
| 分区使用量 | `gopsutil/disk.Usage()` | 获取指定挂载点使用情况 |
| 内置/外置识别 | `diskutil info` 命令 | 解析 "Internal:" 字段 |
| 磁盘 IO | `gopsutil/disk.IOCounters()` | 读写字节数（差值计算速率） |

**关键特性：**

1. **智能过滤系统分区：**
```go
var skipDiskMounts = map[string]bool{
    "/System/Volumes/VM":       true,
    "/System/Volumes/Preboot":  true,
    "/System/Volumes/Data":     true,
    ...
}
```

2. **内置/外置磁盘识别：**
```go
func isExternalDisk(device string) (bool, error) {
    out, _ := runCmd(ctx, "diskutil", "info", device)
    // 解析 "Internal: No" 或 "Device Location: External"
    ...
}
```

3. **IO 速率计算（差值法）：**
```go
func (c *Collector) collectDiskIO(now time.Time) DiskIOStatus {
    counters, _ := disk.IOCounters()
    elapsed := now.Sub(c.lastDiskAt).Seconds()
    
    readRate := float64(total.ReadBytes - c.prevDiskIO.ReadBytes) / 1024 / 1024 / elapsed
    writeRate := float64(total.WriteBytes - c.prevDiskIO.WriteBytes) / 1024 / 1024 / elapsed
    ...
}
```

---

### 4.3 电源/电池监控 (metrics_battery.go)

**你关注的显示效果：**
```
Level  ████████████████  100.0%
Discharging · 10:32 · 18446744073709544W
Normal · 691 cycles · 30°C
```

#### 技术实现：

```go
type BatteryStatus struct {
    Percent    float64  // 电量百分比
    Status     string   // 状态: Charging/Discharging/Charged
    TimeLeft   string   // 剩余时间
    Health     string   // 健康状态: Normal/Service Recommended
    CycleCount int      // 充电周期数
    Capacity   int      // 最大容量百分比
}

type ThermalStatus struct {
    CPUTemp      float64  // CPU 温度
    FanSpeed     int      // 风扇转速
    SystemPower  float64  // 系统功耗 (W)
    AdapterPower float64  // 适配器功率 (W)
    BatteryPower float64  // 电池放电功率 (W)
}
```

**数据采集方式：**

| 指标 | 采集方式 | 说明 |
|------|----------|------|
| 电量/状态 | `pmset -g batt` | 实时电量和充电状态 |
| 健康/周期 | `system_profiler SPPowerDataType` | 电池健康信息（30s 缓存） |
| 温度 | `ioreg -rn AppleSmartBattery` | 从 IORegistry 获取 |
| 功耗 | `ioreg -rn AppleSmartBattery` | SystemPowerIn/BatteryPower 字段 |
| 风扇 | `system_profiler SPPowerDataType` | 解析风扇速度字段 |

**关键代码：**

```go
// 解析 pmset 输出获取实时电量
func parsePMSet(raw string, health string, cycles int, capacity int) []BatteryStatus {
    // 输出示例: "InternalBattery-0 (id=123)	85%; charging; 0:45 remaining"
    for line := range strings.Lines(raw) {
        if strings.Contains(line, "%") {
            // 解析百分比和状态
        }
    }
}

// 从 ioreg 获取温度和功耗
func collectThermal() ThermalStatus {
    out, _ := runCmd(ctx, "ioreg", "-rn", "AppleSmartBattery")
    // 解析 "Temperature" = 3055 -> 30.55°C
    // 解析 "SystemPowerIn" = 12500 -> 12.5W
    // 解析 "BatteryPower" = 8000 -> 8.0W
}
```

---

### 4.4 进程监控 (metrics_process.go)

**你关注的显示效果：**
```
WindowServer  ▮▯▯▯▯   21.6%
iTerm2        ▯▯▯▯▯   18.2%
(Renderer)    ▯▯▯▯▯    9.6%
```

#### 技术实现：

```go
type ProcessInfo struct {
    Name   string   // 进程名
    CPU    float64  // CPU 占用百分比
    Memory float64  // 内存占用百分比
}
```

**数据采集方式：**
```go
func collectTopProcesses() []ProcessInfo {
    // 使用 ps 命令获取 CPU 占用最高的进程
    out, _ := runCmd(ctx, "ps", "-Aceo", "pcpu,pmem,comm", "-r")
    // -A: 所有进程
    // -c: 只显示命令名（不含路径）
    // -e: 显示环境
    // -o: 指定输出格式
    // -r: 按 CPU 降序排序
    
    // 取前 5 个进程
    for i := 0; i < 5; i++ {
        // 解析输出
    }
}
```

---

### 4.5 网络监控 (metrics_network.go)

**你关注的显示效果：**
```
Down   ▯▯▯▯▯  0 MB/s
Up     ▯▯▯▯▯  0 MB/s
Proxy HTTP · 192.168.3.8
```

#### 技术实现：

```go
type NetworkStatus struct {
    Name      string   // 接口名 (en0, en1...)
    RxRateMBs float64  // 接收速率 MB/s
    TxRateMBs float64  // 发送速率 MB/s
    IP        string   // IP 地址
}

type ProxyStatus struct {
    Enabled bool    // 是否启用代理
    Type    string  // HTTP/SOCKS/System
    Host    string  // 代理地址
}
```

**数据采集方式：**

| 指标 | 采集方式 | 说明 |
|------|----------|------|
| 网络流量 | `gopsutil/net.IOCounters()` | 每个接口的收发字节数 |
| IP 地址 | `gopsutil/net.Interfaces()` | 接口绑定的 IP |
| 代理状态 | 环境变量 + `scutil --proxy` | 检测系统代理配置 |

**关键特性：**

1. **过滤噪声接口：**
```go
func isNoiseInterface(name string) bool {
    noiseList := []string{"lo", "awdl", "utun", "llw", "bridge", "gif", "stf", "xhc", "anpi", "ap"}
    // 过滤虚拟网络接口
}
```

2. **代理检测：**
```go
func collectProxy() ProxyStatus {
    // 1. 检查环境变量 HTTP_PROXY/HTTPS_PROXY
    // 2. macOS: 检查 scutil --proxy 输出
    //    - HTTPEnable : 1 -> HTTP 代理
    //    - SOCKSEnable : 1 -> SOCKS 代理
}
```

---

### 4.6 健康评分算法 (metrics_health.go)

**健康分数计算权重：**

| 指标 | 权重 | 说明 |
|------|------|------|
| CPU 使用率 | 30% | >30% 开始扣分，>70% 重度扣分 |
| 内存使用率 | 25% | >50% 开始扣分，>80% 重度扣分 |
| 磁盘使用率 | 20% | >70% 警告，>90% 严重 |
| 温度 | 15% | >60°C 开始扣分，>85°C 过热 |
| 磁盘 IO | 10% | >50MB/s 开始扣分，>150MB/s 重度 |

**评分区间：**
- 90-100: Excellent (绿色)
- 75-89: Good (浅绿色)
- 60-74: Fair (黄色)
- 40-59: Poor (橙色)
- 0-39: Critical (红色)

---

## 5. 性能优化策略

### 5.1 并发采集
```go
func (c *Collector) Collect() (MetricsSnapshot, error) {
    var wg sync.WaitGroup
    
    // 并发启动所有采集任务
    collect := func(fn func() error) {
        wg.Add(1)
        go func() {
            defer wg.Done()
            fn()
        }()
    }
    
    collect(func() error { cpuStats, _ = collectCPU(); return nil })
    collect(func() error { memStats, _ = collectMemory(); return nil })
    collect(func() error { diskStats, _ = collectDisks(); return nil })
    // ... 其他采集任务
    
    wg.Wait()
}
```

### 5.2 分层缓存策略

| 数据类型 | 缓存时间 | 原因 |
|----------|----------|------|
| 硬件信息 | 10 分钟 | 几乎不变 |
| 蓝牙设备 | 30 秒 | 采集较慢 |
| 电池健康 | 30 秒 | system_profiler 较慢 |
| 磁盘类型 | 2 分钟 | diskutil 调用 |
| GPU 信息 | 5 秒 | 变化较慢 |
| 实时指标 | 1 秒 | 需要实时更新 |

### 5.3 命令超时控制
```go
// 所有外部命令都有超时保护
ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
defer cancel()
out, err := runCmd(ctx, "command", "args...")
```

---

## 6. UI 渲染 (view.go)

### 6.1 进度条渲染
```go
func progressBar(percent float64) string {
    total := 16  // 16 字符宽度
    filled := int(percent / 100 * float64(total))
    
    var builder strings.Builder
    for i := 0; i < total; i++ {
        if i < filled {
            builder.WriteString("█")  // 实心块
        } else {
            builder.WriteString("░")  // 空心块
        }
    }
    return colorizePercent(percent, builder.String())
}
```

### 6.2 颜色编码
```go
func colorizePercent(percent float64, s string) string {
    switch {
    case percent >= 85:
        return dangerStyle.Render(s)   // 红色 #FF5F5F
    case percent >= 60:
        return warnStyle.Render(s)     // 黄色 #FFD75F
    default:
        return okStyle.Render(s)       // 绿色 #A5D6A7
    }
}
```

### 6.3 IO 速率条
```go
func ioBar(rate float64) string {
    filled := min(int(rate/10.0), 5)  // 每 10MB/s 一格
    bar := strings.Repeat("▮", filled) + strings.Repeat("▯", 5-filled)
    // 根据速率着色
}
```

---

## 7. 对 menu-stats 的借鉴价值

### 7.1 可复用的技术方案

| 功能 | macOS 实现方案 | Swift 等效 |
|------|----------------|------------|
| 内存信息 | `vm_stat` / `memory_pressure` | `host_statistics64()` / `ProcessInfo` |
| 磁盘信息 | `diskutil info` | `DiskArbitration` 框架 |
| 电池信息 | `pmset -g batt` / `ioreg` | `IOKit` / `IOPSCopyPowerSourcesInfo` |
| 网络流量 | `netstat` / gopsutil | `SystemConfiguration` / `NWPathMonitor` |
| 进程列表 | `ps -Aceo` | `libproc` / `proc_listpids` |
| 系统代理 | `scutil --proxy` | `CFNetworkCopySystemProxySettings` |

### 7.2 推荐移植的设计模式

1. **分层缓存** - 减少频繁的系统调用
2. **并发采集** - 提高数据刷新效率
3. **命令超时** - 防止阻塞主线程
4. **健康评分算法** - 综合评估系统状态
5. **噪声过滤** - 磁盘/网络接口的智能过滤

---

## 8. 关键文件索引

```
Mole/cmd/status/
├── main.go              # 入口、Bubble Tea 模型
├── metrics.go           # 数据收集器、核心数据结构
├── metrics_cpu.go       # CPU 监控
├── metrics_memory.go    # 内存监控
├── metrics_disk.go      # 磁盘监控
├── metrics_battery.go   # 电池/温度监控
├── metrics_network.go   # 网络监控
├── metrics_process.go   # 进程监控
├── metrics_hardware.go  # 硬件信息
├── metrics_health.go    # 健康评分算法
└── view.go              # UI 渲染
```
