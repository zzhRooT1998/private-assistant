import Foundation
import PhotosUI
import SwiftUI
import UIKit
import PrivateAssistantShared

@MainActor
final class AppModel: ObservableObject {
    @Published var baseURLString: String
    @Published var textInput = ""
    @Published var pageURLString = ""
    @Published var sourceApp = ""
    @Published var sourceType: SourceType = .manual
    @Published var selectedImageData: Data?
    @Published var selectedImageFilename: String?
    @Published var selectedImageContentType: String?
    @Published var lastResponse: MobileIntakeResponse?
    @Published var ledgerEntries: [LedgerEntry] = []
    @Published var todoEntries: [TodoEntry] = []
    @Published var referenceEntries: [ReferenceEntry] = []
    @Published var scheduleEntries: [ScheduleEntry] = []
    @Published var isSubmitting = false
    @Published var isRefreshingActivity = false
    @Published var errorMessage: String?

    private let configurationStore: ConfigurationStore
    private let client: PrivateAssistantAPIClient
    private let iso8601Formatter = ISO8601DateFormatter()

    init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        client: PrivateAssistantAPIClient? = nil
    ) {
        self.configurationStore = configurationStore
        self.client = client ?? PrivateAssistantAPIClient(configurationStore: configurationStore)
        self.baseURLString = configurationStore.loadBaseURLString()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func saveBaseURL() {
        configurationStore.saveBaseURLString(baseURLString)
    }

    func loadSelectedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = data
                selectedImageFilename = item.itemIdentifier.map { "\($0).jpg" } ?? "selected-image.jpg"
                selectedImageContentType = "image/jpeg"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearComposer() {
        textInput = ""
        pageURLString = ""
        sourceApp = ""
        sourceType = .manual
        selectedImageData = nil
        selectedImageFilename = nil
        selectedImageContentType = nil
    }

    func submitCapture() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            saveBaseURL()
            let payload = MobileIntakePayload(
                imageData: selectedImageData,
                imageFilename: selectedImageFilename,
                imageContentType: selectedImageContentType,
                textInput: textInput,
                pageURL: pageURLString,
                sourceApp: sourceApp,
                sourceType: sourceType.rawValue,
                capturedAt: iso8601Formatter.string(from: Date())
            )
            let response = try await client.submitMobileIntake(payload)
            lastResponse = response
            await reloadActivity()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadActivity() async {
        isRefreshingActivity = true
        defer { isRefreshingActivity = false }
        do {
            saveBaseURL()
            async let ledger = client.fetchLedger()
            async let todos = client.fetchTodos()
            async let references = client.fetchReferences()
            async let schedules = client.fetchSchedules()

            ledgerEntries = try await ledger
            todoEntries = try await todos
            referenceEntries = try await references
            scheduleEntries = try await schedules
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var previewImage: UIImage? {
        guard let selectedImageData else { return nil }
        return UIImage(data: selectedImageData)
    }

    var canSubmit: Bool {
        selectedImageData != nil ||
        !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !pageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var totalActivityCount: Int {
        ledgerEntries.count + todoEntries.count + referenceEntries.count + scheduleEntries.count
    }
}
