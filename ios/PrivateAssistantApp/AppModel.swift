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
    @Published var speechText = ""
    @Published var speechConfidence: Double?
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
    @Published var isRecordingSpeech = false
    @Published var isRefreshingActivity = false
    @Published var confirmingReviewID: String?
    @Published var ledgerSearchFilters = LedgerSearchFilters()
    @Published var ledgerFilterOptions = LedgerFilterOptions(categories: [], merchants: [], sortOptions: [], sortOrders: [])
    @Published var isPresentingLedgerFilters = false
    @Published var selectedLedgerDetail: LedgerEntryDetail?
    @Published var isLoadingLedgerDetail = false
    @Published private(set) var activeProductivityActionKeys: Set<String> = []
    @Published var errorMessage: String?

    private let configurationStore: ConfigurationStore
    private let client: PrivateAssistantAPIClient
    private let notificationManager: AppNotificationManager
    private let productivityIntegrationService: ProductivityIntegrationService
    private let speechCaptureService = SpeechCaptureService()
    private let iso8601Formatter = ISO8601DateFormatter()
    private let iso8601FormatterWithoutFractionalSeconds = ISO8601DateFormatter()
    private var lastActivityReloadAt: Date?

    init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        client: PrivateAssistantAPIClient? = nil,
        productivityIntegrationService: ProductivityIntegrationService = ProductivityIntegrationService(),
        notificationManager: AppNotificationManager = .shared
    ) {
        self.configurationStore = configurationStore
        self.client = client ?? PrivateAssistantAPIClient(configurationStore: configurationStore)
        self.productivityIntegrationService = productivityIntegrationService
        self.notificationManager = notificationManager
        self.baseURLString = configurationStore.loadBaseURLString()
        let savedLanguage = UserDefaults.standard.string(forKey: PreferenceKey.language)
        self.language = savedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? AppLanguage.defaultValue
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso8601FormatterWithoutFractionalSeconds.formatOptions = [.withInternetDateTime]

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
        stopSpeechCapture()
        textInput = ""
        speechText = ""
        speechConfidence = nil
        pageURLString = ""
        sourceApp = ""
        sourceType = .manual
        selectedImageData = nil
        selectedImageFilename = nil
        selectedImageContentType = nil
    }

    func submitCapture() async {
        stopSpeechCapture()
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
                speechText: speechText,
                speechConfidence: speechConfidence,
                pageURL: pageURLString,
                sourceApp: sourceApp,
                sourceType: sourceType.rawValue,
                capturedAt: iso8601Formatter.string(from: Date())
            )
            let response = try await client.submitMobileIntake(payload)
            lastResponse = response
            await performAutomaticProductivityActions(for: response)
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
            async let ledger = client.fetchLedger(filters: ledgerSearchFilters)
            async let todos = client.fetchTodos()
            async let references = client.fetchReferences()
            async let schedules = client.fetchSchedules()
            async let pendingReviews = client.fetchPendingIntentReviews()
            async let ledgerFilters = client.fetchLedgerFilterOptions()

            ledgerEntries = try await ledger
            todoEntries = try await todos
            referenceEntries = try await references
            scheduleEntries = try await schedules
            pendingIntentReviews = try await pendingReviews
            ledgerFilterOptions = try await ledgerFilters
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
            await performAutomaticProductivityActions(for: response)
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

    func toggleSpeechCapture() async {
        if isRecordingSpeech {
            stopSpeechCapture()
            return
        }

        errorMessage = nil
        do {
            try await speechCaptureService.startTranscribing(localeIdentifier: language.rawValue) { [weak self] text, confidence in
                self?.speechText = text
                self?.speechConfidence = confidence
            }
            isRecordingSpeech = true
        } catch {
            isRecordingSpeech = false
            errorMessage = error.localizedDescription
        }
    }

    func stopSpeechCapture() {
        speechCaptureService.stopTranscribing()
        isRecordingSpeech = false
    }

    func applyLedgerFilters() async {
        await reloadActivity()
    }

    func resetLedgerFilters() async {
        ledgerSearchFilters = LedgerSearchFilters()
        await reloadActivity()
    }

    func loadLedgerDetail(for entryID: Int) async {
        isLoadingLedgerDetail = true
        errorMessage = nil
        selectedLedgerDetail = nil
        defer { isLoadingLedgerDetail = false }

        do {
            selectedLedgerDetail = try await client.fetchLedgerDetail(entryID: entryID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveTodoToReminders(_ entry: TodoEntry) async {
        let actionKey = todoReminderActionKey(for: entry)
        await performProductivityAction(actionKey) { [self] in
            try await self.productivityIntegrationService.saveTodoToReminders(entry)
            await self.notificationManager.notify(
                title: self.strings.notificationTitle,
                body: self.strings.notificationBodyForReminderSaved(title: entry.title)
            )
        }
    }

    func saveScheduleToCalendar(_ entry: ScheduleEntry) async {
        let actionKey = scheduleCalendarActionKey(for: entry)
        await performProductivityAction(actionKey) { [self] in
            try await self.productivityIntegrationService.saveScheduleToCalendar(entry)
            await self.notificationManager.notify(
                title: self.strings.notificationTitle,
                body: self.strings.notificationBodyForCalendarSaved(title: entry.title)
            )
        }
    }

    func scheduleAlarm(forTodo entry: TodoEntry) async {
        let actionKey = todoAlarmActionKey(for: entry)
        await performProductivityAction(actionKey) { [self] in
            try await self.productivityIntegrationService.scheduleAlarm(forTodo: entry)
            await self.notificationManager.notify(
                title: self.strings.notificationTitle,
                body: self.strings.notificationBodyForAlarmScheduled(title: entry.title)
            )
        }
    }

    func scheduleAlarm(forSchedule entry: ScheduleEntry) async {
        let actionKey = scheduleAlarmActionKey(for: entry)
        await performProductivityAction(actionKey) { [self] in
            try await self.productivityIntegrationService.scheduleAlarm(forSchedule: entry)
            await self.notificationManager.notify(
                title: self.strings.notificationTitle,
                body: self.strings.notificationBodyForAlarmScheduled(title: entry.title)
            )
        }
    }

    func isPerformingProductivityAction(_ key: String) -> Bool {
        activeProductivityActionKeys.contains(key)
    }

    func todoReminderActionKey(for entry: TodoEntry) -> String {
        "todo-reminder-\(entry.id)"
    }

    func todoAlarmActionKey(for entry: TodoEntry) -> String {
        "todo-alarm-\(entry.id)"
    }

    func scheduleCalendarActionKey(for entry: ScheduleEntry) -> String {
        "schedule-calendar-\(entry.id)"
    }

    func scheduleAlarmActionKey(for entry: ScheduleEntry) -> String {
        "schedule-alarm-\(entry.id)"
    }

    var supportsSystemAlarm: Bool {
        productivityIntegrationService.supportsSystemAlarm
    }

    func canScheduleAlarm(for entry: TodoEntry) -> Bool {
        guard let dueAt = entry.dueAt, let dueDate = parseISO8601Date(dueAt) else {
            return false
        }
        return dueDate > Date()
    }

    func canScheduleAlarm(for entry: ScheduleEntry) -> Bool {
        guard let startDate = parseISO8601Date(entry.startAt) else {
            return false
        }
        return startDate > Date()
    }

    var previewImage: UIImage? {
        guard let selectedImageData else { return nil }
        return UIImage(data: selectedImageData)
    }

    var canSubmit: Bool {
        selectedImageData != nil ||
        !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !pageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var totalActivityCount: Int {
        ledgerEntries.count + todoEntries.count + referenceEntries.count + scheduleEntries.count
    }

    var ledgerVisibleTotalAmount: Decimal {
        ledgerEntries.reduce(into: Decimal.zero) { partialResult, entry in
            partialResult += Decimal(string: entry.actualAmount) ?? .zero
        }
    }

    var ledgerLatestAmount: String {
        ledgerEntries.first?.actualAmount ?? "0"
    }

    var strings: AppStrings {
        AppStrings(language: language)
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        iso8601Formatter.date(from: value) ?? iso8601FormatterWithoutFractionalSeconds.date(from: value)
    }

    private func performAutomaticProductivityActions(for response: MobileIntakeResponse) async {
        var failures: [String] = []

        if let entry = response.todoEntry {
            do {
                try await productivityIntegrationService.saveTodoToReminders(entry)
            } catch {
                failures.append(error.localizedDescription)
            }

            if supportsSystemAlarm, canScheduleAlarm(for: entry) {
                do {
                    try await productivityIntegrationService.scheduleAlarm(forTodo: entry)
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
        }

        if let entry = response.scheduleEntry {
            do {
                try await productivityIntegrationService.saveScheduleToCalendar(entry)
            } catch {
                failures.append(error.localizedDescription)
            }

            if supportsSystemAlarm, canScheduleAlarm(for: entry) {
                do {
                    try await productivityIntegrationService.scheduleAlarm(forSchedule: entry)
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
        }

        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    private func performProductivityAction(
        _ key: String,
        operation: @escaping @MainActor () async throws -> Void
    ) async {
        guard !activeProductivityActionKeys.contains(key) else {
            return
        }

        errorMessage = nil
        activeProductivityActionKeys.insert(key)
        defer {
            activeProductivityActionKeys.remove(key)
        }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
