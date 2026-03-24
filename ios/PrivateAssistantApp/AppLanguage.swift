import Foundation
import PrivateAssistantShared

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "中文"
        }
    }

    static var defaultValue: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chineseSimplified : .english
    }
}

struct AppStrings {
    let language: AppLanguage

    var captureTab: String { localized(en: "Capture", zh: "采集") }
    var activityTab: String { localized(en: "Activity", zh: "动态") }
    var ledgerTab: String { localized(en: "Ledger", zh: "账本") }
    var settingsTab: String { localized(en: "Settings", zh: "设置") }

    var requestFailed: String { localized(en: "Request Failed", zh: "请求失败") }
    var ok: String { localized(en: "OK", zh: "确定") }

    var captureTitle: String { localized(en: "Capture", zh: "采集") }
    var heroTitle: String { localized(en: "Turn a screen into an action", zh: "把一张截图变成可执行动作") }
    var heroDescription: String {
        localized(
            en: "Paste text, attach a screenshot, or drop in a page URL. The assistant will classify the capture and execute bookkeeping, todo, reference, or schedule workflows.",
            zh: "贴入文字、附上截图，或输入页面链接。助手会识别内容，并执行记账、待办、收藏或日程流程。"
        )
    }
    var liveIntake: String { localized(en: "Live Intake", zh: "实时解析") }
    func savedCount(_ count: Int) -> String { localized(en: "\(count) Saved", zh: "已保存 \(count) 条") }
    var contextSection: String { localized(en: "Context", zh: "上下文") }
    var sharedText: String { localized(en: "Shared Text", zh: "共享文本") }
    var sharedTextPlaceholder: String { localized(en: "Paste message text or notes", zh: "粘贴消息文本或备注") }
    var pageURL: String { localized(en: "Page URL", zh: "页面链接") }
    var sourceApp: String { localized(en: "Source App", zh: "来源应用") }
    var sourceAppPlaceholder: String { localized(en: "Safari, WeChat, Photos", zh: "Safari、微信、照片") }
    var sourceType: String { localized(en: "Source Type", zh: "来源类型") }
    var screenshotSection: String { localized(en: "Screenshot", zh: "截图") }
    var chooseScreenshot: String { localized(en: "Choose Screenshot", zh: "选择截图") }
    var replaceScreenshot: String { localized(en: "Replace Screenshot", zh: "替换截图") }
    var attached: String { localized(en: "Attached", zh: "已附加") }
    var screenshotHint: String {
        localized(
            en: "Attach a receipt, article page, map, or a message screenshot.",
            zh: "可上传收据、文章页面、地图页面或聊天截图。"
        )
    }
    var actionsSection: String { localized(en: "Actions", zh: "操作") }
    var sendToAssistant: String { localized(en: "Send To Assistant", zh: "发送给助手") }
    var clearDraft: String { localized(en: "Clear Draft", zh: "清空草稿") }
    var latestResult: String { localized(en: "Latest Result", zh: "最新结果") }
    var pendingDecisionTitle: String { localized(en: "Need Your Decision", zh: "需要你来确认") }
    var pendingDecisionSubtitle: String {
        localized(
            en: "The model saw multiple likely intents. Pick one of the top candidates or type your own supported intent.",
            zh: "模型识别出了多个可能意图。请选择前三候选之一，或手动输入支持的意图。"
        )
    }
    var suggestedIntents: String { localized(en: "Top 3 Suggestions", zh: "前三候选") }
    var customIntentTitle: String { localized(en: "Custom Intent", zh: "自定义意图") }
    var customIntentPlaceholder: String {
        localized(en: "bookkeeping / todo / reference / schedule", zh: "记账 / 待办 / 收藏 / 日程")
    }
    var confirmCustomIntent: String { localized(en: "Use Custom Intent", zh: "使用自定义意图") }
    var confirming: String { localized(en: "Confirming…", zh: "确认中…") }
    var pendingReviewContext: String { localized(en: "Capture Context", zh: "采集上下文") }
    var refreshPendingReviews: String { localized(en: "Refresh Pending Reviews", zh: "刷新待确认任务") }
    var queuedShortcutNotice: String {
        localized(
            en: "Shortcuts can send screenshots in the background. Open the app after a moment to review ambiguous cases.",
            zh: "快捷指令会在后台发送截图。稍后打开 App，可以处理模型拿不准的场景。"
        )
    }
    var sourceLabel: String { localized(en: "Source", zh: "来源") }
    var confidence: String { localized(en: "Confidence", zh: "置信度") }
    var actionLabel: String { localized(en: "Action", zh: "动作") }
    var amountLabel: String { localized(en: "Amount", zh: "金额") }

    var activityTitle: String { localized(en: "Activity", zh: "动态") }
    var todos: String { localized(en: "Todos", zh: "待办") }
    var references: String { localized(en: "References", zh: "收藏") }
    var schedule: String { localized(en: "Schedule", zh: "日程") }
    var noActivity: String { localized(en: "No captured activity yet", zh: "还没有新的动态") }
    var noActivityHint: String {
        localized(
            en: "Send a screenshot or text from the Capture tab and the saved items will appear here.",
            zh: "从采集页发送截图或文本后，保存的内容会显示在这里。"
        )
    }

    var ledgerTitle: String { localized(en: "Ledger", zh: "账本") }
    var entries: String { localized(en: "Entries", zh: "条目数") }
    var latest: String { localized(en: "Latest", zh: "最新金额") }
    var noLedger: String { localized(en: "No bookkeeping entries yet", zh: "还没有账单记录") }
    var noLedgerHint: String {
        localized(
            en: "Upload a receipt or payment screenshot from the Capture tab to create your first ledger item.",
            zh: "从采集页上传收据或支付截图后，这里会出现第一条账单。"
        )
    }
    func occurredAt(_ value: String) -> String { localized(en: "Occurred: \(value)", zh: "发生时间：\(value)") }

    var settingsTitle: String { localized(en: "Settings", zh: "设置") }
    var backend: String { localized(en: "Backend", zh: "后端") }
    var serverBaseURL: String { localized(en: "Server Base URL", zh: "服务地址") }
    var saveEndpoint: String { localized(en: "Save Endpoint", zh: "保存地址") }
    var currentEndpoint: String { localized(en: "Current Endpoint", zh: "当前地址") }
    var notes: String { localized(en: "Notes", zh: "说明") }
    var noteSimulator: String {
        localized(
            en: "Use 127.0.0.1 only in the iOS Simulator. On a physical iPhone, replace it with your public tunnel or your Mac's LAN IP.",
            zh: "仅在 iOS 模拟器中使用 127.0.0.1。真机测试时，请改成公网隧道地址或 Mac 的局域网 IP。"
        )
    }
    var notePersonalTeam: String {
        localized(
            en: "This build avoids App Groups so it can run with a Personal Team account. Update the endpoint separately inside the main app if the extension still points at an older value.",
            zh: "当前构建为了兼容 Personal Team，未启用 App Groups。如果分享扩展还指向旧地址，请在主 App 中单独更新。"
        )
    }
    var languageSection: String { localized(en: "Language", zh: "语言") }
    var notificationSection: String { localized(en: "Notifications", zh: "通知") }
    var enableNotifications: String { localized(en: "Enable Notifications", zh: "开启通知") }
    var notificationHelp: String {
        localized(
            en: "Show a local notification when a task is saved or when new activity is detected after refresh.",
            zh: "在任务保存成功，或刷新后发现新动态时，发送本地通知。"
        )
    }

    var notificationTitle: String { localized(en: "Private Assistant", zh: "私人助手") }
    func notificationBody(for response: MobileIntakeResponse) -> String {
        switch response.intent {
        case "bookkeeping":
            if let entry = response.ledgerEntry {
                let merchant = entry.merchant ?? localized(en: "Unknown Merchant", zh: "未知商户")
                return localized(en: "Saved bookkeeping entry for \(merchant), amount \(entry.actualAmount).", zh: "已保存账单：\(merchant)，金额 \(entry.actualAmount)。")
            }
        case "todo":
            if let entry = response.todoEntry {
                return localized(en: "Saved todo: \(entry.title).", zh: "已保存待办：\(entry.title)。")
            }
        case "reference":
            if let entry = response.referenceEntry {
                return localized(en: "Saved reference: \(entry.title).", zh: "已保存收藏：\(entry.title)。")
            }
        case "schedule":
            if let entry = response.scheduleEntry {
                return localized(en: "Saved schedule: \(entry.title).", zh: "已保存日程：\(entry.title)。")
            }
        default:
            break
        }
        return response.message
    }

    func notificationBodyForNewItems(count: Int) -> String {
        localized(en: "\(count) new item(s) synced.", zh: "已同步 \(count) 条新内容。")
    }

    func notificationBodyForPendingReview(count: Int) -> String {
        localized(
            en: "\(count) item(s) need your intent confirmation.",
            zh: "有 \(count) 条内容需要你确认意图。"
        )
    }

    func localizedIntent(_ intent: String) -> String {
        switch intent {
        case "bookkeeping":
            return localized(en: "Bookkeeping", zh: "记账")
        case "todo":
            return localized(en: "Todo", zh: "待办")
        case "reference":
            return localized(en: "Reference", zh: "收藏")
        case "schedule":
            return localized(en: "Schedule", zh: "日程")
        default:
            return localized(en: "Unknown", zh: "未知")
        }
    }

    func localizedSourceType(_ sourceType: SourceType) -> String {
        switch sourceType {
        case .manual:
            return localized(en: "Manual", zh: "手动")
        case .screenshot:
            return localized(en: "Screenshot", zh: "截图")
        case .onscreen:
            return localized(en: "On Screen", zh: "屏幕内容")
        case .shareExtension:
            return localized(en: "Share Extension", zh: "分享扩展")
        }
    }

    func localizedSourceType(_ sourceType: String?) -> String {
        guard let sourceType, let resolved = SourceType(rawValue: sourceType) else {
            return sourceType ?? localized(en: "Unknown", zh: "未知")
        }
        return localizedSourceType(resolved)
    }

    func shortcutQueuedTitle() -> String {
        localized(en: "Queued For Analysis", zh: "已加入解析队列")
    }

    func shortcutQueuedMessage() -> String {
        localized(
            en: "Your screenshot is on its way. Open Private Assistant in a few seconds to review or confirm the result.",
            zh: "截图已经发出。几秒后打开 Private Assistant 查看结果，必要时确认意图。"
        )
    }

    func shortcutSendFailedTitle() -> String {
        localized(en: "Screenshot Send Failed", zh: "截图发送失败")
    }

    func shortcutSendFailedMessage(_ detail: String) -> String {
        localized(
            en: "Private Assistant could not reach the server. \(detail)",
            zh: "Private Assistant 没有成功连接到后端。\(detail)"
        )
    }

    func shortcutSendSucceededTitle() -> String {
        localized(en: "Screenshot Sent", zh: "截图已发送")
    }

    func shortcutSendSucceededMessage(_ intent: String?) -> String {
        let fallback = localized(
            en: "The screenshot reached the assistant. Open the app in a moment to review the result.",
            zh: "截图已经发到助手。稍后打开 App 查看结果。"
        )
        guard let intent, !intent.isEmpty else {
            return fallback
        }
        return localized(
            en: "The screenshot reached the assistant. Current top intent: \(localizedIntent(intent)). Open the app in a moment to review the result.",
            zh: "截图已经发到助手。当前首要意图：\(localizedIntent(intent))。稍后打开 App 查看结果。"
        )
    }

    func shortcutMissingScreenshotMessage() -> String {
        localized(
            en: "No screenshot was provided. Run Take Screenshot before this shortcut.",
            zh: "没有收到截图。请先执行“截屏”，再运行这个快捷指令。"
        )
    }

    func shortcutUnreadableScreenshotMessage() -> String {
        localized(
            en: "The screenshot could not be read. Try taking it again.",
            zh: "截图读取失败，请重新截一次。"
        )
    }

    private func localized(en: String, zh: String) -> String {
        language == .chineseSimplified ? zh : en
    }
}
