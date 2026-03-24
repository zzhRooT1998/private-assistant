import Foundation
import PhotosUI
import SwiftUI
import UIKit
import PrivateAssistantShared

@MainActor
final class AppModel: ObservableObject {
    private enum PreferenceKey {
        static let language = "app_language"
    }

    @Published var baseURLString: String
    @Published var language: AppLanguage
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
    @Published var pendingIntentReviews: [IntentReview] = []
    @Published var isSubmitting = false
    @Published var isRefreshingActivity = false
    @Published var confirmingReviewID: String?
    @Published var errorMessage: String?

    private let configurationStore: ConfigurationStore
    private let client: PrivateAssistantAPIClient
    private let notificationManager: AppNotificationManager
    private let iso8601Formatter = ISO8601DateFormatter()
    private var lastActivityReloadAt: Date?

    init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        client: PrivateAssistantAPIClient? = nil,
        notificationManager: AppNotificationManager = .shared
    ) {
        self.configurationStore = configurationStore
        self.client = client ?? PrivateAssistantAPIClient(configurationStore: configurationStore)
        self.notificationManager = notificationManager
        self.baseURLString = configurationStore.loadBaseURLString()
        let savedLanguage = UserDefaults.standard.string(forKey: PreferenceKey.language)
        self.language = savedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? AppLanguage.defaultValue
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        Task {
            await notificationManager.requestAuthorizationIfNeeded()
        }
    }

    func saveBaseURL() {
        configurationStore.saveBaseURLString(baseURLString)
    }

    func saveLanguage() {
        UserDefaults.standard.set(language.rawValue, forKey: PreferenceKey.language)
    }

    func requestNotificationAuthorization() async {
        await notificationManager.requestAuthorizationIfNeeded()
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
            if response.requiresConfirmation {
                await notificationManager.notify(
                    title: strings.notificationTitle,
                    body: strings.notificationBodyForPendingReview(count: 1)
                )
            } else {
                await notificationManager.notify(title: strings.notificationTitle, body: strings.notificationBody(for: response))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadActivity() async {
        isRefreshingActivity = true
        defer { isRefreshingActivity = false }
        do {
            saveBaseURL()
            let previousCount = totalActivityCount
            let previousPendingReviewCount = pendingIntentReviews.count
            let hadPreviousReload = lastActivityReloadAt != nil
            async let ledger = client.fetchLedger()
            async let todos = client.fetchTodos()
            async let references = client.fetchReferences()
            async let schedules = client.fetchSchedules()
            async let pendingReviews = client.fetchPendingIntentReviews()

            ledgerEntries = try await ledger
            todoEntries = try await todos
            referenceEntries = try await references
            scheduleEntries = try await schedules
            pendingIntentReviews = try await pendingReviews
            lastActivityReloadAt = Date()
            let newCount = totalActivityCount
            if previousCount > 0, newCount > previousCount {
                let delta = newCount - previousCount
                await notificationManager.notify(
                    title: strings.notificationTitle,
                    body: strings.notificationBodyForNewItems(count: delta)
                )
            }
            if hadPreviousReload, pendingIntentReviews.count > previousPendingReviewCount {
                let delta = pendingIntentReviews.count - previousPendingReviewCount
                await notificationManager.notify(
                    title: strings.notificationTitle,
                    body: strings.notificationBodyForPendingReview(count: delta)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmIntentReview(_ review: IntentReview, selectedIntent: String? = nil, customIntent: String? = nil) async {
        confirmingReviewID = review.id
        errorMessage = nil
        defer { confirmingReviewID = nil }

        do {
            saveBaseURL()
            let response = try await client.confirmIntentReview(
                reviewID: review.id,
                selectedIntent: selectedIntent,
                customIntent: customIntent
            )
            lastResponse = response
            pendingIntentReviews.removeAll { $0.id == review.id }
            await reloadActivity()
            await notificationManager.notify(title: strings.notificationTitle, body: strings.notificationBody(for: response))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshActivityIfNeeded() async {
        if isRefreshingActivity {
            return
        }

        let shouldReload: Bool
        if let lastActivityReloadAt {
            shouldReload = Date().timeIntervalSince(lastActivityReloadAt) > 2
        } else {
            shouldReload = true
        }

        if shouldReload {
            await reloadActivity()
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

    var strings: AppStrings {
        AppStrings(language: language)
    }
}
