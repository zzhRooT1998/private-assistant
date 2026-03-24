# 2026-03-24 iOS Debugging Notes

这份文档记录本次 iOS 真机接入、快捷指令、后端模型兼容过程中踩到的实际问题，按“现象 -> 根因 -> 修复”整理。

## 1. 页面上下黑边，看起来没有全屏

现象：
- App 页面顶部和底部出现黑边
- 背景色没有铺满整个 iPhone 屏幕

根因：
- SwiftUI 页面背景最初挂在 `ScrollView.background(...)` 上，容器层级不对
- 更关键的是工程最初缺少 `Launch Screen`
- 在刘海屏设备上，缺 Launch Screen 时系统会按兼容模式启动，直接表现成上下黑边

修复：
- 页面改成 `ZStack + ignoresSafeArea`
- 新增 `ios/PrivateAssistantApp/LaunchScreen.storyboard`
- 在 `ios/Configs/PrivateAssistantApp-Info.plist` 里补 `UILaunchStoryboardName = LaunchScreen`

结论：
- 这类问题不一定是 SwiftUI 布局本身，先排查 Launch Screen

## 2. DashScope + qwen3-vl-plus 返回 502

现象：
- `/agent/life/mobile-intake` 返回 `502 Bad Gateway`
- 后端日志出现：
  `Unsupported model: qwen3-vl-plus`
  或
  `Model response did not include text output`

根因：
- 后端最初统一走 OpenAI `responses.create`
- 当前 `.env` 实际使用：
  - `OPENAI_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1`
  - `OPENAI_MODEL=qwen3-vl-plus`
- DashScope 这条兼容链路对该视觉模型应走 `chat.completions`，不是 `responses.create`

修复：
- 在 `app/services/vision.py` 中按 provider 分支：
  - DashScope `compatible-mode/v1` -> `chat.completions.create`
  - 其他兼容 provider -> `responses.create`
- 补充响应解析兼容逻辑，支持更多返回结构

验证：
- 直接本地调用 `VisionIntentService.parse_input(...)` 成功
- 本地 HTTP 调 `POST /agent/life/mobile-intake` 返回 `200`

## 3. 模型识别成功，但接口返回 422

现象：
- 后端不再 502，但偶发返回 `422 Unprocessable Content`
- 用户截图重新进入 App 后能看到数据，说明有些请求其实已经执行成功

根因：
- 模型有时会判断出 `todo/reference/schedule/bookkeeping`
- 但缺少业务执行需要的关键字段，例如 schedule 缺开始时间
- 原逻辑在 `_execute_intent()` 中直接抛 `422`

修复：
- 在 `app/main.py` 中改成降级逻辑：
  - normalize 成功 -> 执行业务
  - normalize 失败 -> 仅返回识别结果，不抛 422

结论：
- “模型识别” 和 “业务可执行” 不是同一层
- 执行失败应该尽量退化，而不是整体请求失败

## 4. 快捷指令 `Receive What's On Screen` 不稳定

现象：
- 快捷指令里 `Get What's On Screen` + `Send To Private Assistant` 经常失败
- 常见错误包括类型不匹配、空输入、快捷指令编辑页里拿不到真实目标页面

根因：
- `What's On Screen` 的输出类型不稳定，可能是 URL、文本、图片
- 用户目标是“只上传截图”，并不需要多类型输入

修复：
- 放弃 `Get What's On Screen`
- 收窄成：
  `Take Screenshot -> Send To Private Assistant`
- `SendToPrivateAssistantIntent` 只保留截图输入

结论：
- 如果业务只关心图片，不要引入 `What's On Screen`

## 5. 快捷指令执行被系统中断，但数据其实已经落库

现象：
- iPhone 通知中心里提示：
  `操作 "Send To Private Assistant" 被中断，因为未及时完成执行`
- 或提示 app 在快捷指令执行中退出
- 但重新打开 App 后，数据其实已经能看到

根因：
- 快捷指令原先等待完整上传 + 模型解析 + 后端执行 + 返回结果
- iOS 对后台 shortcut 执行时长很敏感
- 后端已成功，但 shortcut 在等待结果时被系统打断

修复：
- `ios/PrivateAssistantApp/Intents/SendToPrivateAssistantIntent.swift`
  改成“排队发送后立即返回”
- `ios/PrivateAssistantShared/PrivateAssistantAPIClient.swift`
  新增 `enqueueMobileIntake(_:)`
- shortcut 不再等完整结果，而是提示用户稍后打开 App 查看
- 同时对截图先转 JPEG，缩短上传体积

结论：
- 快捷指令适合“快速触发”，不适合长时间等待模型结果

## 6. App 超时，但后端其实稍后完成了

现象：
- App 显示超时或请求失败
- 重新打开后发现账单/任务已经出现在列表里

根因：
- 默认网络超时偏短
- 截图上传 + 视觉模型解析耗时波动大

修复：
- 在 `ios/PrivateAssistantShared/PrivateAssistantAPIClient.swift` 显式配置：
  - request timeout: 30s
  - resource timeout: 180s
  - upload timeout: 180s
- 对超时错误单独给出清晰提示

结论：
- 视觉上传链路必须显式设更长 timeout

## 7. 下拉刷新不生效，必须杀掉 App 再进

现象：
- 用户在 `Ledger` / `Activity` 页下拉没有刷新
- 必须退出再进入 App 才能看到新数据

根因：
- `.refreshable` 最初挂在 `NavigationStack` 上，而不是真正的 `ScrollView`
- App 回到前台时也没有统一自动刷新

修复：
- 把 `.refreshable` 改挂到 `ScrollView`
- 在 `ios/PrivateAssistantApp/RootView.swift` 监听 `scenePhase`
- 在 `ios/PrivateAssistantApp/AppModel.swift` 增加 `refreshActivityIfNeeded()`

结论：
- SwiftUI 下拉刷新必须挂在可滚动容器上
- 快捷指令和前台切换的场景，要在 app 激活时补刷新

## 8. 真机安装失败：Share Extension 缺 `NSExtension`

现象：
- Xcode 安装失败
- 报错：
  `does not define an NSExtension dictionary in its Info.plist`

根因：
- `ios/Configs/PrivateAssistantShareExtension-Info.plist` 中 `NSExtension` 字典丢失

修复：
- 补回：
  - `NSExtensionPointIdentifier = com.apple.share-services`
  - `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).ShareViewController`
  - `NSExtensionActivationRule = TRUEPREDICATE`

## 9. 真机安装失败：Share Extension 缺 `CFBundleDisplayName`

现象：
- Xcode 安装失败
- 报错：
  `does not have a CFBundleDisplayName key with a non-zero length string value`

根因：
- iOS 26 对 `.appex` 的元数据校验更严格
- 分享扩展 plist 中没有 `CFBundleDisplayName`

修复：
- 在：
  - `ios/Configs/PrivateAssistantShareExtension-Info.plist`
  - `ios/Configs/PrivateAssistantApp-Info.plist`
  中补 `CFBundleDisplayName`

## 10. XcodeGen 工程新增 Swift 文件后，Xcode 编译说找不到类型

现象：
- 新增 Swift 文件后，Xcode 编译报：
  - `cannot find 'AppLanguage' in scope`
  - `cannot find type 'AppStrings' in scope`

根因：
- 工程是由 `xcodegen generate` 生成的
- 新文件加到目录里后，当前 `.xcodeproj` 不会自动更新

修复：
- 重新执行：

```bash
cd ios
/opt/homebrew/bin/xcodegen generate
```

结论：
- 每次新增源文件后，都要记得重生成工程

## 11. `Take Screenshot -> App Intent` 可能触发沙箱读权限错误

现象：
- 快捷指令日志出现：
  `_INIssueSandboxExtensionWithTokenGeneratorBlock Could not create sandbox read extension ... Operation not permitted`

根因：
- `Take Screenshot` 产出的临时文件在 `WorkflowKit.BackgroundShortcutRunner` 沙箱里
- App Intent 如果把它当普通文件路径来读，系统不一定会正确发放读权限

修复：
- `SendToPrivateAssistantIntent` 的截图参数显式声明为图片内容输入
- 读取时优先通过 `IntentFile.data(contentType: .image)` 拿数据
- 仍然保留 JPEG 压缩，降低后台链路耗时

结论：
- Shortcut 传图片时，尽量按“内容类型”读取，不要依赖临时文件 URL

## 12. 多意图场景不能直接自动执行

现象：
- 一张截图里同时像“待办”和“收藏”，模型首选项并不稳定
- 如果直接执行，容易把用户想“收藏”的内容误落成“待办”

根因：
- 单次分类不是所有截图都能形成足够大的置信差
- 对模糊截图自动执行，风险高于多一步确认

修复：
- 后端增加 LangChain + LangGraph 编排：
  - 先做 intent ranking
  - 当 top1/top2 过近时，创建 pending review
  - 返回前三候选意图
- App 前台刷新时主动拉取 pending review
- 采集页展示前三候选按钮，并允许用户手输支持的意图

结论：
- 模糊截图要走 HITL，不能为了自动化牺牲正确率

## 当前实现策略

目前这套 iOS 方案采用的是：

- 快捷指令：
  - `Take Screenshot -> Send To Private Assistant`
  - shortcut 只负责把截图送出去，不等待完整结果
- App：
  - 前台进入自动刷新
  - 支持中英切换
  - 成功保存后发送本地通知
  - 如果模型拿不准，会拉起待确认意图卡片，展示前三候选
- 后端：
  - 支持 DashScope `qwen3-vl-plus`
  - 执行失败时降级为“仅识别”
  - 多意图场景通过 HITL 确认后再执行

## 后续可继续改进

- 将 `TRUEPREDICATE` 收紧成具体的分享规则，避免未来上架被拒
- 如果要“后端任务完成后无论 app 是否活着都通知手机”，需要接 APNs 远程推送，而不是仅靠本地通知
- 可以为快捷指令链路单独设计一个轻量前台确认页，进一步降低被系统中断的概率
