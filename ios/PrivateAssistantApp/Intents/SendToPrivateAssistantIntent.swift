import AppIntents
import Foundation
import PrivateAssistantShared
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@available(iOS 18.0, *)
enum SendToPrivateAssistantIntentError: LocalizedError {
    case missingScreenshot
    case unreadableScreenshot

    var errorDescription: String? {
        let strings = AppStrings(language: shortcutLanguage)
        switch self {
        case .missingScreenshot:
            return strings.shortcutMissingScreenshotMessage()
        case .unreadableScreenshot:
            return strings.shortcutUnreadableScreenshotMessage()
        }
    }
}

@available(iOS 18.0, *)
struct SendToPrivateAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Send To Private Assistant"
    static let description = IntentDescription("Queue a screenshot and optional dictated command for intent analysis, then surface any follow-up confirmation inside the app.")
    static let openAppWhenRun = false

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile?

    @Parameter(title: "Spoken Command")
    var spokenCommand: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let screenshot else {
            throw SendToPrivateAssistantIntentError.missingScreenshot
        }
        let loadedScreenshot = try await loadImageData(from: screenshot)
        guard let loadedScreenshot else {
            throw SendToPrivateAssistantIntentError.unreadableScreenshot
        }
        let payload = MobileIntakePayload(
            imageData: loadedScreenshot.data,
            imageFilename: loadedScreenshot.filename,
            imageContentType: loadedScreenshot.contentType,
            speechText: normalizedSpokenCommand,
            sourceType: ShortcutSourceType.screenshot.rawValue,
            capturedAt: ISO8601DateFormatter().string(from: Date())
        )
        let client = PrivateAssistantAPIClient()
        let strings = AppStrings(language: shortcutLanguage)
        try client.enqueueMobileIntake(payload, completion: { result in
            switch result {
            case let .success(response):
                Task {
                    await sendShortcutNotification(
                        title: strings.shortcutSendSucceededTitle(),
                        body: strings.shortcutSendSucceededMessage(response.intent)
                    )
                }
            case let .failure(error):
                let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Task {
                    await sendShortcutNotification(
                        title: strings.shortcutSendFailedTitle(),
                        body: strings.shortcutSendFailedMessage(detail)
                    )
                }
            }
        })
        return .result(
            dialog: IntentDialog(
                stringLiteral: normalizedSpokenCommand == nil
                    ? strings.shortcutQueuedMessage()
                    : strings.shortcutQueuedWithSpeechMessage()
            )
        )
    }

    private var normalizedSpokenCommand: String? {
        let trimmed = spokenCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadImageData(from file: IntentFile?) async throws -> LoadedScreenshot? {
        guard let file else { return nil }
        let originalData: Data
        if #available(iOS 18.0, *) {
            originalData = try await file.data(contentType: .image)
        } else {
            guard let fileURL = file.fileURL else {
                return nil
            }
            originalData = try Data(contentsOf: fileURL)
        }

        if let image = UIImage(data: originalData),
           let jpegData = image.jpegData(compressionQuality: 0.78) {
            return LoadedScreenshot(
                data: jpegData,
                filename: Self.normalizedJPEGFilename(from: file.filename),
                contentType: "image/jpeg"
            )
        }

        let fallbackFilename = file.filename.isEmpty ? "capture.jpg" : file.filename
        return LoadedScreenshot(
            data: originalData,
            filename: fallbackFilename,
            contentType: UTType.image.preferredMIMEType ?? "image/jpeg"
        )
    }
    private static func normalizedJPEGFilename(from filename: String) -> String {
        guard !filename.isEmpty else {
            return "capture.jpg"
        }
        let nsFilename = filename as NSString
        let basename = nsFilename.deletingPathExtension
        return basename.isEmpty ? "capture.jpg" : "\(basename).jpg"
    }
}

@available(iOS 18.0, *)
@MainActor
private func sendShortcutNotification(title: String, body: String) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
        return
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
    )
    try? await center.add(request)
}

@available(iOS 18.0, *)
private var shortcutLanguage: AppLanguage {
    let preferred = Locale.preferredLanguages.first ?? "en"
    return preferred.hasPrefix("zh") ? .chineseSimplified : .english
}

private struct LoadedScreenshot {
    let data: Data
    let filename: String
    let contentType: String
}

@available(iOS 18.0, *)
enum ShortcutSourceType: String, AppEnum {
    case screenshot
    case onscreen
    case manual

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Source Type")
    static let caseDisplayRepresentations: [ShortcutSourceType: DisplayRepresentation] = [
        .screenshot: DisplayRepresentation(title: "Screenshot"),
        .onscreen: DisplayRepresentation(title: "On Screen"),
        .manual: DisplayRepresentation(title: "Manual"),
    ]
}

@available(iOS 18.0, *)
struct PrivateAssistantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: SendToPrivateAssistantIntent(),
                phrases: [
                    "Send to \(.applicationName)",
                    "Send screenshot to \(.applicationName)",
                    "Send screenshot and command to \(.applicationName)",
                ],
                shortTitle: "Send Capture",
                systemImageName: "camera.macro"
            )
        ]
    }
}
