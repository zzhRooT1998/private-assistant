import EventKit
import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif
import PrivateAssistantShared

@MainActor
final class ProductivityIntegrationService {
    enum IntegrationError: LocalizedError {
        case remindersPermissionDenied
        case calendarPermissionDenied
        case alarmPermissionDenied
        case reminderCalendarUnavailable
        case eventCalendarUnavailable
        case missingDueDate
        case invalidDate
        case alarmUnavailable
        case alarmMustBeInFuture

        var errorDescription: String? {
            switch self {
            case .remindersPermissionDenied:
                return "Reminder access was denied. Enable Reminders permission in Settings."
            case .calendarPermissionDenied:
                return "Calendar access was denied. Enable Calendar permission in Settings."
            case .alarmPermissionDenied:
                return "Alarm access was denied. Enable alarm permission in Settings."
            case .reminderCalendarUnavailable:
                return "No reminder list is available for new items."
            case .eventCalendarUnavailable:
                return "No calendar is available for new events."
            case .missingDueDate:
                return "This item does not have a usable reminder time yet."
            case .invalidDate:
                return "The saved time could not be parsed on this device."
            case .alarmUnavailable:
                return "System alarms require iOS 26.1 or later."
            case .alarmMustBeInFuture:
                return "Only future times can be scheduled as alarms."
            }
        }
    }

    private let eventStore = EKEventStore()
    private let iso8601WithFractionalSeconds = ISO8601DateFormatter()
    private let iso8601WithoutFractionalSeconds = ISO8601DateFormatter()

    init() {
        iso8601WithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso8601WithoutFractionalSeconds.formatOptions = [.withInternetDateTime]
    }

    func saveTodoToReminders(_ entry: TodoEntry) async throws {
        try await requestReminderAccessIfNeeded()

        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw IntegrationError.reminderCalendarUnavailable
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = entry.title

        let notes = composeNotes(details: entry.details, sourceApp: entry.sourceApp, pageURL: entry.pageURL)
        if !notes.isEmpty {
            reminder.notes = notes
        }

        if let dueAt = entry.dueAt, let dueDate = parseDate(dueAt) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                in: .current,
                from: dueDate
            )
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        try eventStore.save(reminder, commit: true)
    }

    func saveScheduleToCalendar(_ entry: ScheduleEntry) async throws {
        try await requestCalendarAccessIfNeeded()

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw IntegrationError.eventCalendarUnavailable
        }

        guard let startDate = parseDate(entry.startAt) else {
            throw IntegrationError.invalidDate
        }

        let proposedEndDate = entry.endAt.flatMap(parseDate)
        let endDate = normalizedEndDate(startDate: startDate, proposedEndDate: proposedEndDate)

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = entry.title
        event.startDate = startDate
        event.endDate = endDate

        let notes = composeNotes(details: entry.details, sourceApp: entry.sourceApp, pageURL: entry.pageURL)
        if !notes.isEmpty {
            event.notes = notes
        }

        let leadTime: TimeInterval = startDate.timeIntervalSinceNow > 300 ? -300 : 0
        event.addAlarm(EKAlarm(relativeOffset: leadTime))

        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    var supportsSystemAlarm: Bool {
        if #available(iOS 26.1, *), _alarmKitAvailable {
            return true
        }
        return false
    }

    func scheduleAlarm(forTodo entry: TodoEntry) async throws {
        guard let dueAt = entry.dueAt, let dueDate = parseDate(dueAt) else {
            throw IntegrationError.missingDueDate
        }

        let details = composeNotes(details: entry.details, sourceApp: entry.sourceApp, pageURL: entry.pageURL)
        try await scheduleAlarm(title: entry.title, notes: details, fireDate: dueDate)
    }

    func scheduleAlarm(forSchedule entry: ScheduleEntry) async throws {
        guard let startDate = parseDate(entry.startAt) else {
            throw IntegrationError.invalidDate
        }

        let details = composeNotes(details: entry.details, sourceApp: entry.sourceApp, pageURL: entry.pageURL)
        try await scheduleAlarm(title: entry.title, notes: details, fireDate: startDate)
    }

    private func requestReminderAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .authorized:
            return
        case .notDetermined:
            let granted = try await requestReminderAccess()
            guard granted else {
                throw IntegrationError.remindersPermissionDenied
            }
        case .writeOnly, .denied, .restricted:
            throw IntegrationError.remindersPermissionDenied
        @unknown default:
            throw IntegrationError.remindersPermissionDenied
        }
    }

    private func requestCalendarAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .writeOnly, .fullAccess, .authorized:
            return
        case .notDetermined:
            let granted = try await requestCalendarAccess()
            guard granted else {
                throw IntegrationError.calendarPermissionDenied
            }
        case .denied, .restricted:
            throw IntegrationError.calendarPermissionDenied
        @unknown default:
            throw IntegrationError.calendarPermissionDenied
        }
    }

    private func requestReminderAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestCalendarAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestWriteOnlyAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func parseDate(_ value: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: value) ?? iso8601WithoutFractionalSeconds.date(from: value)
    }

    private func normalizedEndDate(startDate: Date, proposedEndDate: Date?) -> Date {
        guard let proposedEndDate else {
            return startDate.addingTimeInterval(3600)
        }

        if proposedEndDate > startDate {
            return proposedEndDate
        }

        return startDate.addingTimeInterval(3600)
    }

    private func composeNotes(details: String?, sourceApp: String?, pageURL: String?) -> String {
        var lines: [String] = []

        if let details, !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(details)
        }
        if let sourceApp, !sourceApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Source App: \(sourceApp)")
        }
        if let pageURL, !pageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Page URL: \(pageURL)")
        }

        return lines.joined(separator: "\n")
    }

    private var _alarmKitAvailable: Bool {
        #if canImport(AlarmKit)
        return true
        #else
        return false
        #endif
    }

    private func scheduleAlarm(title: String, notes: String, fireDate: Date) async throws {
        guard fireDate > Date() else {
            throw IntegrationError.alarmMustBeInFuture
        }

        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) {
            let authorizationState = try await AlarmManager.shared.requestAuthorization()
            guard authorizationState == .authorized else {
                throw IntegrationError.alarmPermissionDenied
            }

            let metadata = PrivateAssistantAlarmMetadata(title: title, note: notes.isEmpty ? nil : notes)
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource("Private Assistant Alarm"))
            let presentation = AlarmPresentation(alert: alert)
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: metadata,
                tintColor: Color(red: 0.82, green: 0.33, blue: 0.12)
            )
            let configuration = AlarmManager.AlarmConfiguration<PrivateAssistantAlarmMetadata>.alarm(
                schedule: .fixed(fireDate),
                attributes: attributes
            )

            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            return
        }
        #endif

        throw IntegrationError.alarmUnavailable
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct PrivateAssistantAlarmMetadata: AlarmMetadata {
    let title: String
    let note: String?
}
#endif
