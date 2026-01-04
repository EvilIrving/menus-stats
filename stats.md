# Stats 开源项目技术分析文档

## 文档概述

本文档全面分析开源项目 Stats（exelban/stats）的技术实现方案、数据获取方法、系统 API 使用以及架构设计思路，为 swift-menu-stats 项目提供技术参考和借鉴依据。

## 项目背景

### 项目基本信息

| 维度 | 信息 |
|------|------|
| 项目名称 | Stats - macOS system monitor |
| 技术栈 | Swift 5.0+, macOS 10.15+ |
| 开源协议 | MIT License |
| 核心定位 | macOS 菜单栏系统监控工具 |
| 支持语言 | 40+ 种语言国际化 |

### 核心价值

Stats 项目实现了一个完整的 macOS 系统监控解决方案，具有以下核心价值：

- 提供精确的系统资源实时监控能力
- 支持多种硬件和系统指标的综合展示
- 采用模块化设计，易于扩展和维护
- 使用公开和底层系统 API 实现深度数据采集

---

## 功能模块分析

### 模块清单

Stats 项目包含 9 个独立功能模块：

| 模块名称 | 监控对象 | 主要功能 | 技术难度 |
|---------|---------|---------|---------|
| CPU | 处理器 | 使用率、温度、频率、进程监控 | 高 |
| GPU | 图形处理器 | 利用率、温度、风扇、进程监控 | 高 |
| RAM | 内存 | 使用量、压力、交换区、进程监控 | 中 |
| Disk | 磁盘 | 容量、活动、SMART 状态 | 中高 |
| Network | 网络 | 带宽、连接状态、WiFi 信息、公网 IP | 中 |
| Battery | 电池 | 电量、健康度、充放电状态 | 中 |
| Sensors | 传感器 | 温度、电压、电流、功率 | 高 |
| Bluetooth | 蓝牙 | 设备列表、电量、连接状态 | 低 |
| Clock | 时钟 | 多时区时间显示 | 低 |

---

## 技术实现方案

### CPU 模块实现

#### 数据获取方法

**1. CPU 使用率获取**

通过 Mach 系统调用获取每个核心的使用率：

- 使用 API：`host_processor_info()` 与 `PROCESSOR_CPU_LOAD_INFO`
- 数据结构：采集 USER、SYSTEM、NICE、IDLE 四种状态时间
- 计算逻辑：对比前后两次采样的差值计算使用率
- 核心特性：支持区分性能核心和效率核心（Apple Silicon）

**2. CPU 温度监控**

针对不同芯片平台使用不同的 SMC 传感器键：

| 平台 | 传感器键列表 | 说明 |
|------|------------|------|
| M1 系列 | Tp09, Tp0T, Tp01, Tp05, Tp0D, Tp0H, Tp0L, Tp0P, Tp0X, Tp0b | 10 个温度传感器 |
| M2 系列 | Tp1h, Tp1t, Tp1p, Tp1l, Tp01, Tp05, Tp09, Tp0D, Tp0X, Tp0b, Tp0f, Tp0j | 12 个温度传感器 |
| M3 系列 | Te05, Te0L, Te0P, Te0S, Tf04, Tf09, Tf0A, Tf0B, Tf0D, Tf0E, Tf44, Tf49, Tf4A, Tf4B, Tf4D, Tf4E | 16 个温度传感器 |
| M4 系列 | Te05, Te09, Te0H, Te0S, Tp01, Tp05, Tp09, Tp0D, Tp0V, Tp0Y, Tp0b, Tp0e | 12 个温度传感器 |
| Intel | TC0D, TC0E, TC0F, TC0P, TC0H | 主要温度传感器 |

通过 SMC 接口读取，计算平均值或选择特定传感器。

**3. CPU 频率监控**

使用 IOReport 框架获取实时频率：

- 数据源：`IOReportCopyChannelsInGroup()` 获取 CPU 性能状态
- 通道组：CPU Stats / CPU Complex Performance States
- 采样方式：创建订阅，周期性采样计算频率
- 计算方法：基于 CPU 各频率状态的驻留时间加权平均

**4. 进程监控**

通过系统命令获取进程信息：

- 命令：`/bin/ps -Aceo pid,pcpu,comm -r`
- 参数说明：按 CPU 使用率排序，输出进程 ID、CPU 占用、命令名
- 数据处理：正则表达式解析，获取应用本地化名称

**5. CPU 限制状态**

使用 pmset 工具查询热管理状态：

- 命令：`/usr/bin/pmset -g therm`
- 监控指标：调度限制、CPU 数量限制、速度限制

**6. 平均负载**

使用 uptime 命令获取系统负载：

- 命令：`/usr/bin/uptime`
- 提取数据：1 分钟、5 分钟、15 分钟平均负载

#### 使用的系统 API

| API 类别 | API 名称 | 访问权限 | 功能说明 |
|---------|---------|---------|---------|
| Mach Kernel | host_processor_info | 公开 | 获取处理器信息和状态 |
| Mach Kernel | host_statistics | 公开 | 获取主机统计信息 |
| IOKit | IOReportCopyChannelsInGroup | 公开 | 获取 IO 性能通道 |
| IOKit | IOReportCreateSubscription | 公开 | 创建性能数据订阅 |
| IOKit | IOReportCreateSamples | 公开 | 创建性能采样 |
| SMC | AppleSMC 服务 | 非公开 | 读取系统管理控制器数据 |
| System | sysctl/sysctlbyname | 公开 | 获取系统配置信息 |

---

### RAM 模块实现

#### 数据获取方法

**1. 内存使用统计**

通过 Mach 虚拟内存统计接口获取：

- 使用 API：`host_statistics64()` 与 `HOST_VM_INFO64`
- 数据结构：`vm_statistics64_data_t`
- 关键指标：
  - Active：活跃内存
  - Inactive：非活跃内存
  - Wired：联动内存
  - Compressed：压缩内存
  - Speculative：推测内存
  - Purgeable：可清除内存
  - External：外部内存

**2. 内存压力监控**

通过 sysctl 获取内存压力等级：

- 系统调用：`sysctlbyname("kern.memorystatus_vm_pressure_level")`
- 压力等级：
  - Normal（正常）：值为其他
  - Warning（警告）：值为 2
  - Critical（危急）：值为 4

**3. 交换区监控**

获取虚拟内存交换使用情况：

- 系统调用：`sysctlbyname("vm.swapusage")`
- 数据结构：`xsw_usage`
- 统计指标：总量、已用、可用交换空间

**4. 进程内存监控**

使用 top 命令获取内存占用进程：

- 命令：`/usr/bin/top -l 1 -o mem -n N -stats pid,command,mem`
- 数据处理：解析输出，支持单位转换（KB、MB、GB）
- 进程合并：支持按责任进程分组显示（使用 `responsibility_get_pid_responsible_for_pid`）

#### 使用的系统 API

| API 类别 | API 名称 | 访问权限 | 功能说明 |
|---------|---------|---------|---------|
| Mach Kernel | host_info | 公开 | 获取主机基本信息（总内存） |
| Mach Kernel | host_statistics64 | 公开 | 获取虚拟内存统计 |
| System | sysctlbyname | 公开 | 获取内存压力和交换区信息 |
| System | dlsym | 公开 | 动态加载责任进程函数 |

---

### Disk 模块实现

#### 数据获取方法

**1. 磁盘容量监控**

通过 DiskArbitration 和 FileManager 获取：

- 使用框架：DiskArbitration.framework
- 核心 API：
  - `DASessionCreate()`：创建磁盘仲裁会话
  - `DADiskCreateFromVolumePath()`：从卷路径创建磁盘对象
  - `DADiskGetBSDName()`：获取 BSD 设备名称
- 容量计算：
  - 使用 `statfs()` 获取文件系统统计
  - 使用 `CSDiskSpaceGetRecoveryEstimate()` 获取可恢复空间
  - 可用空间 = 空闲块数 × 块大小 + 可清理空间

**2. SMART 健康监控**

通过 NVMe SMART 接口读取硬盘健康数据：

- 检测方法：检查 IOKit 中的 "NVMe SMART Capable" 属性
- 接口类型：
  - Plugin Interface：`IOCFPlugInInterface`
  - SMART Interface：`IONVMeSMARTInterface`
- 数据采集：
  - 温度：转换开尔文温度为摄氏度
  - 寿命：100 - 已用百分比
  - 读写总量：数据单元数 × 每单元字节数（512KB）
  - 通电次数和时长

**3. 磁盘活动监控**

通过 IOKit 获取磁盘读写统计：

- 服务类型：`IOBlockStorageDriver`
- 统计项：
  - 读操作次数和字节数
  - 写操作次数和字节数
  - 读写延迟时间
- 计算方式：对比前后采样差值计算速率

#### 使用的系统 API

| API 类别 | API 名称 | 访问权限 | 功能说明 |
|---------|---------|---------|---------|
| DiskArbitration | DASessionCreate | 公开 | 创建磁盘管理会话 |
| DiskArbitration | DADiskCreateFromVolumePath | 公开 | 获取磁盘对象 |
| IOKit | IOServiceGetMatchingService | 公开 | 查找 IO 服务 |
| IOKit | IORegistryEntryGetParentEntry | 公开 | 获取父级注册表项 |
| IOKit | IOCreatePlugInInterfaceForService | 公开 | 创建插件接口 |
| CoreServices | CSDiskSpaceGetRecoveryEstimate | 非公开 | 获取可清理空间估计 |

---

### Network 模块实现

#### 数据获取方法

**1. 网络带宽监控**

提供两种数据采集方式：

**方式一：接口级别监控**

- 系统调用：`getifaddrs()` 获取网络接口地址列表
- 数据结构：`ifaddrs` 包含接口名称和统计数据
- 统计信息：从 `if_data` 结构获取上传和下载字节数
- 计算方式：定时采样，计算两次采样的差值得到速率

**方式二：进程级别监控**

- 使用工具：`/usr/bin/nettop`
- 命令参数：`-P -L 1 -n -k [过滤参数]`
- 数据处理：解析 CSV 格式输出，累加所有进程的网络流量

**2. 网络连接状态监控**

使用 SystemConfiguration 框架监控网络可达性：

- 核心类：Reachability（基于 `SCDynamicStore`）
- 监控事件：网络连接/断开事件
- 主接口识别：通过 `State:/Network/Global/IPv4` 获取主网络接口

**3. WiFi 信息获取**

使用 CoreWLAN 框架获取 WiFi 详细信息：

- 框架：CoreWLAN.framework
- 核心类：`CWWiFiClient` 和 `CWInterface`
- 获取信息：
  - 基础：SSID、BSSID、国家代码
  - 信号：RSSI 值、噪声水平
  - 连接：传输速率、PHY 模式
  - 频道：频道号、频段、带宽
  - 安全：安全类型、接口模式

**4. 公网 IP 获取**

通过外部 API 获取公网 IP：

- API 地址：`https://api.mac-stats.com`（主要）
- 备用 API：`https://api.github.com`（更新检查）
- 获取数据：IP 地址、国家、国家代码

**5. VPN 检测**

通过系统代理配置检测 VPN 连接：

- 数据源：`CFNetworkCopySystemProxySettings()`
- 检测方法：检查 `__SCOPED__` 作用域中是否包含 VPN 相关接口（tap、tun、ppp、ipsec）

#### 使用的系统 API

| API 类别 | API 名称 | 访问权限 | 功能说明 |
|---------|---------|---------|---------|
| BSD Socket | getifaddrs | 公开 | 获取网络接口地址 |
| SystemConfiguration | SCDynamicStoreCopyValue | 公开 | 读取系统动态配置 |
| SystemConfiguration | SCNetworkInterfaceCopyAll | 公开 | 获取所有网络接口 |
| CoreWLAN | CWWiFiClient | 公开 | WiFi 客户端管理 |
| CoreFoundation | CFNetworkCopySystemProxySettings | 公开 | 获取系统代理配置 |

---

### GPU 模块实现

#### 数据获取方法

**1. GPU 基本信息获取**

通过 IOKit 的 PCI 设备和加速器服务获取：

- PCI 设备识别：
  - 服务类型：`IOPCIDevice`
  - 过滤条件：IOName 为 "display"
  - 提取数据：设备 ID、供应商 ID、型号名称
  
- 加速器信息：
  - 服务类型：`kIOAcceleratorClassName`
  - IOClass 类型：
    - `nvaccelerator`：NVIDIA GPU
    - `amd`：AMD GPU
    - `intel`：Intel 集成显卡
    - `agx`：Apple Silicon GPU
  - 匹配方式：通过 PCI ID 匹配设备和加速器

**2. GPU 使用率监控**

从性能统计字典获取利用率：

- 数据源：`PerformanceStatistics` 字典
- 监控指标：
  - Device Utilization %：设备总体利用率
  - GPU Activity(%)：GPU 活动百分比
  - Renderer Utilization %：渲染器利用率
  - Tiler Utilization %：平铺器利用率（Apple Silicon）

**3. GPU 温度监控**

多种方式获取温度：

- 性能统计：`Temperature(C)` 字段
- SMC 传感器：
  - AMD 显卡：TGDD 传感器
  - Intel 显卡：TCGC 传感器
- 温度校验：过滤异常值（如 128°C 表示无效）

**4. GPU 频率监控**

从性能统计获取频率信息：

- Core Clock(MHz)：核心频率
- Memory Clock(MHz)：显存频率

**5. GPU 状态监控**

通过 AGC（Apple Graphics Control）信息判断：

- 数据源：`AGCInfo` 字典
- 状态判断：`poweredOffByAGC` 值为 0 表示开启

#### 使用的系统 API

| API 类别 | API 名称 | 访问权限 | 功能说明 |
|---------|---------|---------|---------|
| IOKit | fetchIOService | 公开 | 获取 IO 服务列表 |
| IOKit | IOServiceGetMatchingServices | 公开 | 查找匹配的服务 |
| Metal | MTLCopyAllDevices | 公开 | 获取所有 Metal 设备 |
| SMC | SMC.shared.getValue | 非公开 | 读取温度传感器 |

---

### Battery 模块实现

#### 数据获取方法

**1. 电池状态监控**

使用 IOPowerSources API 获取电池信息：

- 核心 API：
  - `IOPSCopyPowerSourcesInfo()`：获取电源信息
  - `IOPSCopyPowerSourcesList()`：获取电源列表
  - `IOPSGetPowerSourceDescription()`：获取电源描述
- 监控指标：
  - 电源类型：电池供电或交流电
  - 充电状态：是否充电、是否充满
  - 电量百分比：当前容量 / 总容量
  - 剩余时间：放电剩余时间、充电剩余时间
  - 优化充电：是否启用优化充电

**2. 电池健康度监控**

通过 IORegistry 接口读取电池详细信息：

- 服务类型：`AppleSmartBattery`
- 核心参数：
  - CycleCount：充电循环次数
  - DesignCapacity：设计容量
  - MaxCapacity（Intel）或 AppleRawMaxCapacity（ARM）：最大容量
  - AppleRawCurrentCapacity：当前容量
  - BatteryHealth：电池健康状态（仅 Intel）
- 健康度计算：(最大容量 / 设计容量) × 100%

**3. 电流电压监控**

从 IORegistry 读取实时电气参数：

- Amperage：电流（毫安）
- Voltage：电压（毫伏，转换为伏特）
- Temperature：温度（除以 100 转换）

**4. 充电器信息**

获取交流电源适配器信息：

- API：`IOPSCopyExternalPowerAdapterDetails()`
- 数据：适配器功率（瓦特）
- 充电数据：
  - ChargingCurrent：充电电流
  - ChargingVoltage：充电电压

**5. 进程耗电监控**

使用 top 命令按电量排序：

- 命令：`/usr/bin/top -o power -l 2 -n N -stats pid,command,power`
- 说明：执行两次采样，取第二次结果以获得准确数据

**6. 事件驱动更新**

使用 RunLoop 监听电池状态变化：

- API：`IOPSNotificationCreateRunLoopSource()`
- 机制：创建 RunLoop 源，电池状态变化时自动触发回调
- 优势：无需轮询，实时响应变化

#### 使用的系统 API

| API 类别 | API 名称 | 访问权限 | 功能说明 |
|---------|---------|---------|---------|
| IOKit | IOPSCopyPowerSourcesInfo | 公开 | 获取电源信息 |
| IOKit | IOPSGetPowerSourceDescription | 公开 | 获取电源详细描述 |
| IOKit | IOPSCopyExternalPowerAdapterDetails | 公开 | 获取适配器信息 |
| IOKit | IOServiceGetMatchingService | 公开 | 查找电池服务 |
| IOKit | IORegistryEntryCreateCFProperty | 公开 | 读取注册表属性 |
| IOKit | IOPSNotificationCreateRunLoopSource | 公开 | 创建电源通知源 |

---

### Sensors 模块实现

#### 数据获取方法

**1. SMC 传感器读取**

通过 System Management Controller 获取传感器数据：

- 服务类型：`AppleSMC`
- 接口方法：
  - 打开连接：`IOServiceOpen()`
  - 读取数据：`IOConnectCallStructMethod()`
  - 枚举键：通过 `#KEY` 获取总数，遍历读取所有键
- 数据类型支持：
  - 温度：ui8、ui16、ui32、sp78、sp87、sp96、flt、fpe2 等
  - 电压：SP1E、SP3C、SP4B、SP5A、SPA5、SP69、SPB4、SPF0
  - 电流：同电压类型
  - 功率：同电压类型
- 键名规则：
  - T 开头：温度传感器
  - V 开头：电压传感器
  - P 开头：功率传感器
  - I 开头：电流传感器
  - F 开头：风扇传感器

**2. 传感器分类**

根据功能对传感器分组：

| 分组 | 说明 | 典型传感器 |
|------|------|-----------|
| CPU | CPU 相关温度 | Tp09、Tp0T、TC0D、TC0E 等 |
| GPU | GPU 相关温度 | TCGC、TGDD、TG0D 等 |
| Memory | 内存温度 | Ts0P、Ts1P 等 |
| Mainboard | 主板传感器 | Th0H、Th1H、TN0P 等 |
| Power | 电源相关 | Vp0C、Ip0C、Pp0C 等 |
| Battery | 电池传感器 | TB0T、TB1T 等 |
| Fan | 风扇转速 | F0Ac、F1Ac 等 |
| Unknown | 未知传感器 | 动态发现的新传感器 |

**3. Apple Silicon HID 传感器**

在 ARM 架构上使用 HID 接口获取额外传感器：

- 实现函数：`AppleSiliconSensors()`（非公开 API）
- 传感器类型：
  - MTR Temp：各组件温度（CPU、GPU、SOC）
  - 电压和功率数据
- 数据处理：计算平均值和最高值

**4. IOReport 功率传感器**

通过 IOReport 获取功率数据：

- 通道组：能源统计相关通道
- 数据类型：
  - CPU Power：CPU 功耗
  - GPU Power：GPU 功耗
  - ANE Power：神经引擎功耗
  - RAM Power：内存功耗
  - PCI Power：PCI 设备功耗

**5. 风扇控制**

支持读取和设置风扇参数：

- 读取：
  - FNum：风扇数量
  - F[N]Ac：实际转速
  - F[N]Mn：最小转速
  - F[N]Mx：最大转速
- 设置：
  - F[N]Md：风扇模式（自动/手动）
  - F[N]Tg：目标转速
  - FS!：风扇状态寄存器

#### 使用的系统 API

| API 类别 | API 名称 | 访问权限 | 功能说明 |
|---------|---------|---------|---------|
| IOKit | IOServiceMatching | 公开 | 创建服务匹配字典 |
| IOKit | IOServiceOpen | 公开 | 打开 IO 服务连接 |
| IOKit | IOConnectCallStructMethod | 公开 | 调用 IO 连接方法 |
| IOKit | IOReportCopyChannelsInGroup | 公开 | 获取性能报告通道 |
| HID | AppleSiliconSensors | 非公开 | Apple Silicon 传感器（ARM） |

---

### Bluetooth 模块实现

#### 数据获取方法

**1. 蓝牙设备列表获取**

通过 IOBluetooth 框架获取配对设备：

- 框架：IOBluetooth.framework
- 核心类：`IOBluetoothDevice`
- 获取方法：`IOBluetoothDevice.pairedDevices()`
- 设备信息：
  - 名称、地址（MAC）
  - 连接状态
  - RSSI 信号强度
  - 设备类型

**2. 电池电量获取**

针对支持的设备读取电量：

- 支持设备：耳机、鼠标、键盘、触控板等
- 数据源：设备对象的电量属性
- 电量范围：0-100%

#### 使用的系统 API

| API 类别 | API 名称 | 访问权限 | 功能说明 |
|---------|---------|---------|---------|
| IOBluetooth | IOBluetoothDevice.pairedDevices | 公开 | 获取已配对设备列表 |
| IOBluetooth | IOBluetoothDevice 属性 | 公开 | 访问设备状态和属性 |

---

## 架构设计分析

### 整体架构

Stats 采用模块化的分层架构设计：

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                     │
│                      (AppDelegate)                       │
└─────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Settings   │    │    Update    │    │    Remote    │
│    Window    │    │    Manager   │    │    Control   │
└──────────────┘    └──────────────┘    └──────────────┘
                            │
        ┌───────────────────┼───────────────────────────────┐
        ▼                   ▼                               ▼
┌──────────────┐    ┌──────────────┐            ┌──────────────┐
│  Module CPU  │    │  Module GPU  │    ...     │ Module Clock │
└──────────────┘    └──────────────┘            └──────────────┘
        │                   │                           │
        ▼                   ▼                           ▼
┌──────────────┐    ┌──────────────┐            ┌──────────────┐
│   Readers    │    │   Readers    │            │   Readers    │
│   (Data)     │    │   (Data)     │            │   (Data)     │
└──────────────┘    └──────────────┘            └──────────────┘
        │                   │                           │
        ▼                   ▼                           ▼
┌──────────────┐    ┌──────────────┐            ┌──────────────┐
│   Widgets    │    │   Widgets    │            │   Widgets    │
│  (MenuBar)   │    │  (MenuBar)   │            │  (MenuBar)   │
└──────────────┘    └──────────────┘            └──────────────┘
        │                   │                           │
        ▼                   ▼                           ▼
┌──────────────┐    ┌──────────────┐            ┌──────────────┐
│    Popup     │    │    Popup     │            │    Popup     │
│   (Detail)   │    │   (Detail)   │            │   (Detail)   │
└──────────────┘    └──────────────┘            └──────────────┘
        │                   │                           │
        └───────────────────┴───────────────────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │  Kit Library │
                    │  (Shared)    │
                    └──────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│     SMC      │    │   IOKit      │    │   System     │
│   Interface  │    │   Services   │    │   Commands   │
└──────────────┘    └──────────────┘    └──────────────┘
```

### 核心设计模式

#### 1. 模块模式（Module Pattern）

每个功能模块都是独立的 Module 实例：

**职责定义**

- 生命周期管理：初始化、挂载、卸载、终止
- 状态管理：启用/禁用状态
- 配置管理：从 config.plist 读取模块配置
- 组件协调：管理 Readers、Widgets、Popup、Settings

**模块配置结构**

每个模块包含配置文件 config.plist：

| 配置项 | 说明 | 示例 |
|-------|------|------|
| Name | 模块名称 | CPU、RAM、Network |
| State | 默认启用状态 | true/false |
| Symbol | 系统图标名称 | cpu.fill、memorychip.fill |
| Widgets | 支持的小部件列表 | mini、line_chart、bar_chart 等 |
| Settings | 设置选项配置 | 更新间隔、显示选项等 |

#### 2. Reader-Observer 模式

数据采集层使用 Reader 抽象类：

**Reader 基类职责**

- 定时轮询：可配置的采集间隔
- 数据缓存：保存上次读取的值
- 回调机制：数据变化时通知订阅者
- 生命周期：start、stop、pause、resume

**典型 Reader 类型**

| Reader 类型 | 功能 | 更新频率 |
|------------|------|---------|
| UsageReader | 核心使用率数据 | 1-3 秒 |
| ProcessReader | 进程列表数据 | 仅弹窗时更新 |
| TemperatureReader | 温度传感器 | 跟随主 Reader |
| InfoReader | 静态设备信息 | 初始化一次 |

#### 3. Widget 策略模式

菜单栏小部件采用策略模式实现多种展示方式：

**Widget 类型**

| Widget 类型 | 展示形式 | 适用场景 |
|------------|---------|---------|
| mini | 紧凑数字 | 节省空间 |
| line_chart | 折线图 | 趋势展示 |
| bar_chart | 柱状图 | 对比展示 |
| speed | 双行数据 | 网络速率 |
| battery | 电池图标 | 电量显示 |
| text | 纯文本 | 自定义信息 |

**Widget 工厂**

通过 widget_t 枚举配合工厂方法创建具体 Widget 实例，实现类型和实例的解耦。

#### 4. Popup-Portal 分离

弹出详情窗口与数据展示分离：

**Popup 职责**

- 窗口管理：位置、显示/隐藏
- 事件处理：点击外部关闭、拖动
- 动画效果：淡入淡出

**Portal 职责**

- 数据展示：详细统计信息
- 布局管理：自适应内容大小
- 交互元素：按钮、开关、选择器

### 数据流设计

#### 数据流向

```
System APIs → Readers → Module → Widgets → MenuBar
                  │         │
                  │         └──→ Popup → Portal
                  │
                  └──→ Notifications
```

#### 更新机制

**定时更新**

- 每个 Reader 独立的定时器
- 可配置更新间隔（默认 1-3 秒）
- 支持暂停和恢复

**事件驱动更新**

- Battery：监听电源状态变化事件
- Network：监听网络连接变化事件
- Bluetooth：监听设备连接事件

**按需更新**

- Popup 打开时启动 ProcessReader
- Popup 关闭时暂停耗资源的 Reader
- 减少 CPU 和能耗占用

### 存储设计

#### 配置存储

使用 UserDefaults 存储用户配置：

**存储策略**

- 模块级配置：模块名称为前缀
- 全局配置：共享配置项
- 小部件配置：Widget 类型和位置

**典型配置项**

| 配置键模式 | 示例 | 说明 |
|-----------|------|------|
| [Module]_state | CPU_state | 模块启用状态 |
| [Module]_updateInterval | CPU_updateInterval | 更新间隔 |
| [Module]_widget | CPU_widget | 激活的 Widget 类型 |
| [Module]_position | CPU_position | 菜单栏位置 |

#### 共享配置

部分配置使用 App Group 实现跨进程共享：

- Team ID：eu.exelban.Stats
- 用途：小部件扩展访问主应用配置

### SMC 接口封装

#### SMC 单例设计

SMC 类采用单例模式管理系统管理控制器访问：

**核心功能**

- 连接管理：打开和关闭 AppleSMC 服务连接
- 键值读取：通过 4 字符键名读取传感器数据
- 键值写入：设置风扇速度等参数
- 键枚举：获取所有可用的 SMC 键

**数据类型转换**

支持多种 SMC 数据类型的自动转换：

- 整数类型：ui8、ui16、ui32
- 定点数类型：sp78、sp87、sp96、fpe2 等
- 浮点类型：flt
- 字符串类型：fds

**错误处理**

- 返回值检查：所有 IOKit 调用都检查返回值
- 空值处理：无效传感器返回 nil
- 异常值过滤：温度 > 110°C 或 = 0 视为无效

### 线程安全设计

#### 并发策略

**数据采集线程**

- Reader 在后台线程执行数据采集
- 使用 DispatchQueue 隔离不同模块

**UI 更新线程**

- Widget 更新在主线程执行
- 使用 DispatchQueue.main.async 切换线程

**数据同步**

- 使用 NSLock 保护共享数据
- 变量队列（variablesQueue）隔离读写操作

#### 典型线程模型

```
Background Thread (Reader)
    │
    ├─→ Timer Fires
    ├─→ Fetch System Data (Mach/IOKit/SMC)
    ├─→ Process Data
    └─→ Callback with Result
            │
            └─→ Main Thread (Widget)
                    │
                    ├─→ Update UI
                    └─→ Notify Observers
```

### 性能优化策略

#### 1. 延迟初始化

- 仅在模块启用时初始化 Reader
- Popup 打开时才启动详细数据采集

#### 2. 资源池化

- SMC 连接复用：单例模式避免重复连接
- IOKit 服务缓存：减少服务查找次数

#### 3. 采样优化

- CPU 频率：多次采样平均，提高准确性
- 网络流量：差值计算，避免累积误差


#### 5. 能耗管理

- Popup 关闭时暂停高耗资源的 Reader

---

## 关键技术要点

### SMC 接口访问

#### 技术原理

System Management Controller（SMC）是 Mac 的底层硬件管理芯片，通过 IOKit 接口访问。

#### 访问流程

1. 查找服务：使用 `IOServiceMatching("AppleSMC")` 创建匹配字典
2. 获取服务：通过 `IOServiceGetMatchingServices()` 获取服务迭代器
3. 打开连接：使用 `IOServiceOpen()` 建立通信连接
4. 读写数据：通过 `IOConnectCallStructMethod()` 发送控制命令
5. 关闭连接：使用 `IOServiceClose()` 释放资源

#### 数据格式

SMC 键值采用 4 字符编码：

- 第一字符：数据类别（T=温度、V=电压、P=功率、I=电流、F=风扇）
- 后续字符：具体传感器标识

**数据读取步骤**

1. 读取键信息（dataSize、dataType）
2. 读取原始字节数据
3. 根据 dataType 解析为具体数值

#### 常见传感器键

| 传感器类型 | 典型键名 | 说明 |
|-----------|---------|------|
| CPU 温度 | TC0D、TC0P、Tp09 | 不同位置的 CPU 温度 |
| GPU 温度 | TCGC、TGDD | 集成/独立 GPU 温度 |
| 主板温度 | Th0H、TN0P | 主板和北桥温度 |
| 风扇转速 | F0Ac、F1Ac | 各风扇实际转速 |
| 电池温度 | TB0T、TB1T | 电池温度 |
| 环境温度 | TA0P、TA1P | 环境光传感器附近温度 |

### Mach 内核接口

#### 使用场景

Mach 是 macOS 的核心内核，提供底层系统调用接口，主要用于：

- CPU 使用率采集
- 内存统计
- 主机基本信息

#### 核心 API

**CPU 信息获取**

- `host_processor_info()`：获取处理器信息数组
- 参数：主机端口、信息类型、处理器数量、信息数组、信息数量
- 返回：每个核心的 USER、SYSTEM、IDLE、NICE 时间片

**内存信息获取**

- `host_statistics64()`：获取主机统计信息
- 信息类型：`HOST_VM_INFO64` 用于虚拟内存统计
- 返回：各种内存状态的页数

**主机信息获取**

- `host_info()`：获取主机基本信息
- 信息类型：`HOST_BASIC_INFO` 用于获取总内存等

#### 数据处理

**CPU 使用率计算**

```
前后两次采样差值：
inUse = (user2 - user1) + (system2 - system1) + (nice2 - nice1)
total = inUse + (idle2 - idle1)
usage = inUse / total
```

**内存计算**

```
used = active + inactive + speculative + wired + compressed - purgeable - external
free = total - used
```

### IOReport 框架

#### 功能介绍

IOReport 是 Apple 提供的性能数据采集框架，用于获取硬件性能计数器和统计信息。

#### 使用流程

1. 获取通道：`IOReportCopyChannelsInGroup()` 指定组名和子组名
2. 创建订阅：`IOReportCreateSubscription()` 创建数据订阅
3. 采样：`IOReportCreateSamples()` 获取当前采样
4. 计算差值：`IOReportCreateSamplesDelta()` 计算两次采样的差值
5. 解析数据：遍历通道数据，提取所需指标

#### CPU 频率监控应用

**通道配置**

- Group：CPU Stats
- SubGroup：
  - CPU Complex Performance States
  - CPU Core Performance States

**数据提取**

- 通道名称：ECPU0、ECPU1（效率核心）、PCPU0、PCPU1（性能核心）
- 状态驻留：每个核心在各频率状态的驻留时间
- 频率计算：各状态时间占比 × 对应频率，累加得到加权平均频率

#### 功率监控应用

**通道配置**

- 能源相关通道
- 各组件的功耗统计

**数据类型**

- CPU Power、GPU Power、ANE Power、RAM Power 等

### IOKit 服务查询

#### 服务查询方法

**按类名查询**

```
IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(className))
```

常用服务类名：

- `AppleSMC`：系统管理控制器
- `IOPCIDevice`：PCI 设备
- `IOAcceleratorClassName`：图形加速器
- `IOBlockStorageDriver`：块存储驱动
- `AppleSmartBattery`：智能电池
- `IOBluetoothDevice`：蓝牙设备

**属性读取**

通过 `IORegistryEntryCreateCFProperty()` 读取服务属性：

- 设备信息：型号、厂商、序列号
- 性能统计：PerformanceStatistics 字典
- 状态信息：连接状态、电源状态

**遍历注册表**

使用 `IORegistryEntryGetParentEntry()` 向上遍历设备树，找到目标类型的设备。

### 系统命令封装

#### 命令执行框架

使用 `Process` 类（原 `Task`）执行系统命令：

**标准流程**

1. 创建 Process 实例
2. 设置 launchPath（命令路径）
3. 设置 arguments（命令参数）
4. 创建 Pipe 捕获输出
5. 执行并读取结果
6. 解析输出数据

#### 常用命令

| 命令 | 用途 | 输出格式 |
|------|------|---------|
| /bin/ps | 进程 CPU 使用率 | pid pcpu command |
| /usr/bin/top | 内存/电量排序进程 | pid command mem/power |
| /usr/bin/nettop | 网络流量统计 | CSV 格式 |
| /usr/bin/pmset | 电源管理信息 | 文本格式 |
| /usr/bin/uptime | 系统负载 | 文本格式 |
| /usr/sbin/system_profiler | 系统信息 | JSON/XML 格式 |

#### 输出解析

**正则表达式解析**

使用 String 扩展方法：

- `matches()`：匹配整行格式
- `findAndCrop()`：提取并分割字符串
- `find()`：查找匹配模式

**行枚举解析**

使用 `enumerateLines()` 逐行处理输出，适合处理列表数据。

### 数据类型处理

#### 单位转换

**字节单位**

```
Units 结构体提供：
- kilobytes / megabytes / gigabytes / terabytes
- getReadableSpeed()：自动选择单位（KB/s、MB/s、GB/s）
- getReadableMemory()：格式化显示容量
```

**温度单位**

```
UnitTemperature 扩展：
- 支持摄氏度和华氏度
- 根据系统设置或用户配置切换
- temperature() 函数自动转换并格式化
```

**速率计算**

网络和磁盘速率通过两次采样的差值除以时间间隔计算：

```
rate = (current - previous) / interval
```

#### 数据验证

**有效性检查**

- 温度范围：0-110°C，超出视为无效
- 电流范围：< 100A
- 百分比：限制在 0-100% 之间

**异常值处理**

- NaN 检测：使用 `isNaN` 检查计算结果
- 负值过滤：网络速率使用 `max(value, 0)` 避免负数
- 零值替换：某些传感器为 0 时尝试备用数据源

---

## 可借鉴的技术方案

### 1. 模块化架构

**价值**

- 功能解耦：每个模块独立开发和测试
- 灵活组合：用户可选择启用的模块
- 易于扩展：新增模块不影响现有功能

**实现建议**

- 定义统一的 Module 协议
- 使用配置文件驱动模块行为
- 实现模块生命周期管理

### 2. Reader-Observer 数据采集

**价值**

- 职责分离：数据采集和展示逻辑分离
- 灵活调度：支持不同的更新频率
- 资源节省：按需启停数据采集

**实现建议**

- 抽象 Reader 基类
- 实现定时轮询机制
- 支持暂停和恢复

### 3. SMC 传感器访问

**价值**

- 获取底层硬件数据
- 监控温度、电压、风扇等
- Apple 官方未提供的高级功能

**实现建议**

- 封装 SMC 访问接口
- 实现数据类型自动转换
- 建立传感器键映射表

 

### 5. 性能优化

**价值**

- 降低 CPU 占用
- 减少能耗影响
- 提升用户体验

**实现建议**

- 可配置更新间隔
- 延迟初始化和按需加载
- 资源复用和缓存
- 智能暂停机制

### 6. Widget 展示策略

**价值**

- 多种展示形式
- 用户自定义
- 节省菜单栏空间

**实现建议**

- 实现 Widget 工厂
- 支持动态切换
- 提供紧凑和详细模式

### 7. 弹窗详情设计

**价值**

- 提供详细信息
- 支持交互操作
- 不占用主界面空间

**实现建议**

- Popup 窗口管理
- Portal 内容展示
- 按需加载数据

### 8. 配置管理

**价值**

- 用户偏好持久化
- 跨进程配置共享
- 默认值和验证

**实现建议**

- 使用 UserDefaults
- 分层配置结构
- 提供配置迁移

---


---
开源分发 ，仅考虑Apple Silicon，轻量模式，减少启动时的数据采集，延迟加载非关键模块，不加载未开启模块
 
---
 
### 对 swift-menu-stats 的借鉴价值

| 方面 | 可借鉴内容 | 优先级 |
|------|-----------|-------|
| 架构设计 | Module、Reader、Widget 模式 | 高 |
| 数据采集 | Mach、IOKit、SMC 接口封装 | 高 |
| CPU 监控 | 使用率、温度、频率获取方法 | 高 |
| 内存监控 | 虚拟内存统计、压力监控 | 高 |
| 网络监控 | 接口流量、WiFi 信息获取 | 中 |
| 展示方式 | Widget 策略、Popup 详情 | 中 |
| 性能优化 | 按需加载、智能暂停、资源复用 | 中 |
| 配置管理 | 分层配置、默认值、持久化 | 低 |

 
测试文本在对方独树老夫家拉萨会计法； 了