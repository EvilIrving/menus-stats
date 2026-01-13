//
//  SystemAppFilter.swift
//  menu-stats
//
//  系统应用过滤逻辑
//

import Foundation

// MARK: - System App Watch List

/// 系统应用观察名单（只有在此名单中的系统应用才会被统计显示）
/// 支持精确匹配和通配符匹配（以 * 结尾）
let systemAppWatchList: [String] = [
    // ===== 开发工具（推荐观察）=====
    "com.apple.dt.Xcode",                  // Xcode
    // "com.apple.dt.Instruments",            // Instruments
    // "com.apple.FileMerge",                 // FileMerge
    // "com.apple.Accessibility-Inspector",   // 辅助功能检查器
    // "com.apple.dt.GPU-Tools",              // GPU 工具
    
    // ===== 核心系统服务（必须过滤）=====
    // "com.apple.dock",                      // 程序坞
    "com.apple.finder",                    // 访达
    // "com.apple.loginwindow",               // 登录窗口
    // "com.apple.SystemUIServer",            // 系统 UI 服务
    // "com.apple.controlcenter",             // 控制中心
    // "com.apple.notificationcenterui",      // 通知中心
    // "com.apple.Spotlight",                 // 聚焦搜索
    // "com.apple.WindowManager",             // 窗口管理器
    
    // ===== 系统设置 =====
    // "com.apple.Settings",                  // 系统设置 (Ventura+)
    // "com.apple.SystemSettings",            // 系统设置变体
    
    // ===== 系统内置应用 =====
    "com.apple.Safari",                    // Safari 浏览器
    "com.apple.mail",                      // 邮件
    "com.apple.iCal",                      // 日历
    "com.apple.AddressBook",               // 通讯录
    "com.apple.reminders",                 // 提醒事项
    "com.apple.Notes",                     // 备忘录
    "com.apple.Maps",                      // 地图
    "com.apple.weather",                   // 天气
    "com.apple.news",                      // 新闻
    "com.apple.stocks",                    // 股市
    "com.apple.Home",                      // 家庭
    "com.apple.freeform",                  // 无边记
    
    // ===== 媒体应用 =====
    "com.apple.Music",                     // 音乐
    "com.apple.TV",                        // TV
    "com.apple.podcasts",                  // 播客
    "com.apple.iBooksX",                   // 图书
    "com.apple.Photos",                    // 照片
    "com.apple.PhotoBooth",                // Photo Booth
    
    // ===== 通讯应用 =====
    "com.apple.MobileSMS",                 // 信息
    "com.apple.FaceTime",                  // FaceTime
    
    // ===== 工具应用 =====
    "com.apple.Preview",                   // 预览
    "com.apple.TextEdit",                  // 文本编辑
    "com.apple.calculator",                // 计算器
    "com.apple.Dictionary",                // 词典
    "com.apple.VoiceMemos",                // 语音备忘录
    // "com.apple.Screenshot",                // 截图
    "com.apple.ScreenSharing",             // 屏幕共享
    "com.apple.QuickTimePlayerX",          // QuickTime Player
    "com.apple.ActivityMonitor",           // 活动监视器
    "com.apple.Console",                   // 控制台
    "com.apple.DiskUtility",               // 磁盘工具
    "com.apple.Keychain-Access",           // 钥匙串访问
    "com.apple.Terminal",                  // 终端
    "com.apple.appstore",                  // App Store
    "com.apple.FontBook",                  // 字体册
    "com.apple.Stickies",                  // 便笺
    "com.apple.Grapher",                   // Grapher
    "com.apple.DigitalColorMeter",         // 数码测色计
    "com.apple.ColorSyncUtility",          // ColorSync 实用工具
    "com.apple.SystemProfiler",            // 系统信息
    "com.apple.BluetoothFileExchange",     // 蓝牙文件交换
    "com.apple.print.PrinterProxy",        // 打印机代理
    "com.apple.ScriptEditor2",             // 脚本编辑器
    "com.apple.Automator",                 // 自动操作
    // "com.apple.MigrateAssistant",          // 迁移助理
    // "com.apple.bootcampassistant",         // 启动转换助理
    
    // ===== iWork 套件 =====
    "com.apple.iWork.Pages",               // Pages
    "com.apple.iWork.Numbers",             // Numbers
    "com.apple.iWork.Keynote",             // Keynote
    
    // ===== 辅助功能 =====
    "com.apple.VoiceOver",                 // 旁白
    // "com.apple.accessibility.*",           // 辅助功能相关
    
    // ===== 后台服务 =====
    // "com.apple.bird",                      // iCloud 守护进程
    // "com.apple.cloudd",                    // iCloud 服务
    // "com.apple.coreservicesd",             // Core Services
    // "com.apple.cfprefsd",                  // 偏好设置服务
    // "com.apple.sharingd",                  // 共享服务
    // "com.apple.iCloudNotificationAgent",   // iCloud 通知
]

// MARK: - Filter Functions

/// 检查系统应用是否在观察名单中
/// - Parameter bundleId: Bundle ID
/// - Returns: true 表示应该显示（在观察名单中），false 表示不显示
func isSystemAppInWatchList(_ bundleId: String?) -> Bool {
    guard let bundleId = bundleId, !bundleId.isEmpty else { return false }
    
    for pattern in systemAppWatchList {
        if pattern.hasSuffix("*") {
            // 通配符匹配
            let prefix = String(pattern.dropLast())
            if bundleId.hasPrefix(prefix) {
                return true
            }
        } else {
            // 精确匹配
            if bundleId == pattern {
                return true
            }
        }
    }
    return false
}

/// 判断进程是否应该显示
/// - 第三方应用：默认显示
/// - 系统服务/应用：只有在观察名单中才显示
func shouldShowProcess(_ bundleInfo: ProcessBundleInfo) -> Bool {
    // 系统服务（无 .app bundle 的系统进程）
    if bundleInfo.isSystemPath && !bundleInfo.isInAppBundle {
        return false  // 系统服务默认不显示
    }
    
    // 系统应用（有 .app bundle 的 Apple 应用）
    if bundleInfo.isSystemApp {
        // 只有在观察名单中才显示
        return isSystemAppInWatchList(bundleInfo.bundleId)
    }
    
    // 第三方应用：默认显示
    return true
}
