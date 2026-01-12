# Tasks: Menu Stats MVP

## M1: 基础架构

- [x] task001 将 App 改造为状态栏 App（移除主窗口，添加 NSStatusItem）
  - 验证：运行后状态栏显示图标，无主窗口弹出
  
- [x] task002 实现 Popover 容器与 Tab 切换（概览/清理释放）
  - 验证：点击状态栏图标弹出 Popover，可切换 Tab

- [x] task003 实现状态栏文本动态显示框架
  - 验证：状态栏显示动态系统状态文本

## M2: 系统数据采集

- [x] task004 实现 CPU 总使用率采集（Mach API）
  - 验证：CPU 使用率实时更新

- [x] task005 实现单核 CPU 使用率采集
  - 验证：各核心使用率显示

- [x] task006 实现 GPU 利用率采集（IOKit）
  - 验证：GPU 使用率显示（不支持时显示 N/A）

- [x] task007 实现内存统计采集
  - 验证：内存使用量/总量/百分比显示

- [x] task008 实现磁盘/网络/风扇数据采集
  - 验证：各项数据显示

## M3: 概览 Tab

- [x] task009 实现三个圆环饼图（CPU/GPU/MEM）
  - 验证：概览 Tab 显示三个圆环，数值实时更新

- [x] task010 实现系统状态区（温度/风扇/磁盘/网络）
  - 验证：显示各项系统状态文本

- [x] task011 实现核心使用率可滚动列表
  - 验证：显示各核心进度条，颜色随负载变化

## M4: 清理释放 Tab

- [x] task012 实现用户 App 列表获取与展示
  - 验证：显示运行中的用户 App 列表

- [x] task013 实现内存摘要区与列表项内存显示
  - 验证：显示内存使用概览和各 App 内存占用

- [x] task014 实现关闭 App 功能（滑出按钮 + 确认）
  - 验证：悬浮显示关闭按钮，点击可关闭 App

## M5: 设置页面

- [x] task015 实现状态栏显示项设置
  - 验证：可勾选/取消显示项，至少保留一项

- [x] task016 实现其他设置（刷新频率/单位）
  - 验证：设置可保存并生效
  
## M6: Bug 修复

- [ ] task017 修复 SMC 温度/风扇在 Apple Silicon 上不显示的问题 (issue001)
  - 修正 SMCParamStruct 结构体布局（匹配 smctemp.h）
  - 实现两步读取流程 (GetKeyInfo → ReadKey)
  - 扩展 Apple Silicon 温度键列表
  - 验证：在 M2 Pro / M4 上显示 CPU 温度

## M7: 内存详细信息增强

- [x] task018 实现详细内存指标采集（Active/Inactive/Wired/Compressed/Speculative/Purgeable/External）
  - 扩展 MemoryInfo.DetailedInfo 结构体
  - 使用 host_statistics64 + HOST_VM_INFO64 获取 vm_statistics64 数据
  - 验证：调用 getDetailedMemoryInfo() 返回各内存组件值

- [x] task019 实现内存压力等级采集（Normal/Warning/Critical）
  - 使用 sysctlbyname("kern.memorystatus_vm_pressure_level") 获取压力等级
  - 添加 MemoryPressureLevel 枚举类型
  - 验证：getMemoryPressureLevel() 返回正确的压力等级

- [x] task020 实现清理释放 Tab 中间信息区 UI 展示
  - 在 CleanupTabView 中添加 detailedMemorySection
  - 使用 LazyVGrid 展示 7 项内存指标
  - 验证：清理释放 Tab 显示 Active/Inactive/Wired/Compressed/Speculative/Purgeable/External

- [x] task021 实现进度条颜色随内存压力变化
  - memoryBarColor 根据 memoryPressure 等级返回绿/黄/红
  - 验证：进度条颜色随系统内存压力动态变化

## M8: 清理释放 Tab UI 优化

- [x] task023 顶部摘要区优化 - "内存使用中"改为"内存占用"
  - 验证：摘要区标题显示"内存占用"

- [x] task024 App运行数量移到列表上方，修复appCount与列表不一致问题
  - 新增 appCountHeader 组件，置于列表上方
  - 使用 runningApps.count 而非 appCount 确保一致
  - 验证：App 数量显示在列表上方，与实际列表项数一致

- [x] task025 新增缓存环形图和一键清除缓存按钮（横向并排）
  - 新增 cacheSectionView 组件
  - 环形图显示 Purgeable + External 缓存占比
  - 清除缓存按钮触发 triggerMemoryCleanup()
  - 验证：缓存区域显示环形图和清除按钮

- [x] task026 指标区移除Purgeable和External缓存指标
  - detailedMemorySection 仅显示 5 项指标
  - 验证：指标区不显示缓存类指标
