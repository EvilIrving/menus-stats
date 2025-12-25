# Changelog: Menu Stats MVP

按时间倒序记录变更。

---

## 2024-12-25

### task023-026: 清理释放 Tab UI 优化

- **Modify** `AppDelegate.swift` - CleanupTabView 全面重构
  - 修改 "内存使用中" 为 "内存占用"
  - 新增 `cacheSectionView` 缓存操作区（环形图 + 清除按钮）
  - 新增 `appCountHeader` 组件，置于列表上方
  - 修改 `detailedMemorySection` 移除缓存指标
  - 修复 App 数量显示使用 `runningApps.count`
- **Modify** `AppMemoryManager.swift` - 新增内存清理功能
  - 新增 `triggerMemoryCleanup()` 方法
  - 通过内存压力模拟触发系统清理
- **Modify** `docs/ram_prd.md` - 更新界面布局文档
  - 新增 3.2 缓存操作区说明
  - 修改 3.3 内存指标区（移除缓存类）
  - 修改 3.4 App 占用列表（数量移至列表上方）

### task018-021: 内存详细信息增强 (ram_prd.md 第 3.2 节)

- **Modify** `SystemMonitor.swift` - 扩展 MemoryInfo 模块
  - 新增 `MemoryPressureLevel` 枚举（Normal/Warning/Critical）
  - 新增 `MemoryInfo.DetailedInfo` 结构体，包含 7 项内存指标
  - 新增 `getDetailedMemoryInfo()` 获取详细内存统计
  - 新增 `getMemoryPressureLevel()` 通过 sysctl 获取内存压力
  - 新增 `getSwapUsage()` 获取交换区使用情况
- **Modify** `AppMemoryManager.swift` - 支持详细内存数据
  - 新增 `detailedMemory: MemoryInfo.DetailedInfo?` 属性
  - 新增 `memoryPressure: MemoryPressureLevel` 属性
  - 修改 `updateRunningApps()` 使用 `getDetailedMemoryInfo()`
- **Modify** `AppDelegate.swift` - CleanupTabView UI 增强
  - 新增 `detailedMemorySection` 中间信息区
  - 新增 `MemoryStatRow` 组件展示单项内存指标
  - 修改 `memoryBarColor` 根据内存压力等级返回颜色

### task017: 修复 SMC 温度/风扇 Apple Silicon 兼容性 (issue001) - 进行中

- **Modify** `SystemMonitor.swift` - SMCInfo 模块重构
  - 修正 SMCParamStruct 及嵌套结构体布局（匹配 smctemp.h）
  - 移除错误的 `padding: UInt16` 字段
  - 将 UInt8 改为 CChar 以匹配 C 结构体
  - 实现两步读取: kSMCGetKeyInfo(9) → kSMCReadKey(5)
  - 扩展 Apple Silicon 温度键: Tc0a/Tc0b/Tc0x/Tc0z, Tp01-Tp1l
  - 添加 debugSMC() 调试函数，输出到 `/tmp/menu-stats-smc-debug.log`
- **Modify** `AppDelegate.swift` - 启动时调用 SMCInfo.debugSMC()
- **Add** `.phrase/docs/ISSUES.md` - 问题索引
- **Add** `.phrase/phases/phase-mvp-20241224/issue_smc_20241225.md` - issue001 详情

---

## 2024-12-24

### task017: SMC 温度和风扇读取
- **Modify** `SystemMonitor.swift` - 实现完整的 SMC 访问
  - SMCInfo 通过 IOKit 访问 AppleSMC
  - 读取 CPU 温度 (TC0P/TC0C 键)
  - 读取风扇转速 (F0Ac 等键)
- **Add** `menu_stats.entitlements` - 禁用 App Sandbox 以访问 SMC

### task001-003: 基础架构
- **Add** `AppDelegate.swift` - 状态栏 App 核心逻辑，NSStatusItem + Popover
- **Modify** `menu_statsApp.swift` - 移除 SwiftData，改为状态栏 App 入口
- **Add** `Info.plist` - LSUIElement=YES 配置
- **Delete** `ContentView.swift`, `Item.swift` - 移除不需要的模板文件

### task004-008: 系统数据采集
- **Add** `SystemMonitor.swift` - 系统监控核心类
  - CPUInfo: CPU 总使用率 + 单核使用率 (Mach API)
  - MemoryInfo: 内存统计 (vm_statistics64)
  - DiskInfo: 磁盘空间 (URL resourceValues)
  - NetworkInfo: 网络速率 (getifaddrs)
  - GPUInfo: GPU 利用率 (IOKit/IOAccelerator)
  - SMCInfo: 温度/风扇占位 (TODO: 完善 SMC 访问)

### task009-011: 概览 Tab
- **Add** `OverviewTabView` - 概览页面
  - RingView: 圆环饼图 (CPU/GPU/MEM)
  - StatusRow: 系统状态行 (温度/风扇/磁盘/网络)
  - CoreUsageRow: 核心使用率进度条

### task012-014: 清理释放 Tab
- **Add** `AppMemoryManager.swift` - App 内存管理
  - 用户 App 列表获取 (NSWorkspace)
  - 内存占用采集 (task_info/proc_pidinfo)
  - 关闭/强制关闭 App (terminate/forceTerminate)
- **Add** `CleanupTabView` - 清理页面
  - 内存摘要区
  - App 列表 + 悬浮关闭按钮
  - 强制关闭确认弹窗

### task015-016: 设置页面
- **Add** `SettingsManager.swift` - 设置管理类
  - 状态栏显示项开关 (Logo/CPU/GPU/MEM/DISK/NET/FAN)
  - 刷新频率 (低/中/高)
  - 温度/网速单位
  - UserDefaults 持久化
- **Add** `SettingsView.swift` - 设置页面 UI
- **Modify** `AppDelegate.swift` - 集成设置功能，状态栏文本支持设置
