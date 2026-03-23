import AppIntents
import Foundation
import PrivateAssistantShared
import UniformTypeIdentifiers

struct SendToPrivateAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Send To Private Assistant"
    static let description = IntentDescription("Upload a screenshot, URL, or text snippet to the assistant backend for intent analysis.")
    static let openAppWhenRun = false

    @Parameter(title: "Screenshot")
    var screenshot: IntentFile?

    @Parameter(title: "Text")
    var textInput: String?

    @Parameter(title: "URL")
    var pageURL: URL?

    @Parameter(title: "Source App")
    var sourceApp: String?

    @Parameter(title: "Source Type", default: .onscreen)
    var sourceType: ShortcutSourceType

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let imageData = try await loadImageData(from: screenshot)
        let payload = MobileIntakePayload(
            imageData: imageData,
            imageFilename: screenshot?.filename,
            imageContentType: UTType.image.preferredMIMEType,
            textInput: textInput,
            pageURL: pageURL?.absoluteString,
            sourceApp: sourceApp,
            sourceType: sourceType.rawValue,
            capturedAt: ISO8601DateFormatter().string(from: Date())
        )
        let client = PrivateAssistantAPIClient()
        let response = try await client.submitMobileIntake(payload)
        let dialog = response.analysis?.summary ?? response.message
        return .result(dialog: "\(dialog)")
    }

    private func loadImageData(from file: IntentFile?) async throws -> Data? {
        guard let file else { return nil }
        if #available(iOS 18.0, *) {
            return try await file.data(contentType: .image)
        }
        guard let fileURL = file.fileURL else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }
}

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

struct PrivateAssistantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: SendToPrivateAssistantIntent(),
                phrases: [
                    "Send to \(.applicationName)",
                    "Capture with \(.applicationName)",
                ],
                shortTitle: "Send Capture",
                systemImageName: "camera.viewfinder"
            )
        ]
    }
}
