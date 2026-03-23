import Foundation

public enum SourceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case screenshot
    case onscreen
    case shareExtension = "share_extension"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .screenshot:
            return "Screenshot"
        case .onscreen:
            return "On Screen"
        case .shareExtension:
            return "Share Extension"
        }
    }
}

public struct ScreenIntentAnalysis: Codable, Equatable, Sendable {
    public let intent: String
    public let action: String?
    public let confidence: Double
    public let summary: String?
    public let sourceApp: String?
    public let sourceType: String?
    public let pageURL: String?
    public let extractedText: String?
    public let merchant: String?
    public let currency: String?
    public let originalAmount: String?
    public let discountAmount: String?
    public let actualAmount: String?
    public let categoryGuess: String?
    public let occurredAt: String?

    enum CodingKeys: String, CodingKey {
        case intent
        case action
        case confidence
        case summary
        case sourceApp = "source_app"
        case sourceType = "source_type"
        case pageURL = "page_url"
        case extractedText = "extracted_text"
        case merchant
        case currency
        case originalAmount = "original_amount"
        case discountAmount = "discount_amount"
        case actualAmount = "actual_amount"
        case categoryGuess = "category_guess"
        case occurredAt = "occurred_at"
    }

    public init(
        intent: String,
        action: String?,
        confidence: Double,
        summary: String?,
        sourceApp: String?,
        sourceType: String?,
        pageURL: String?,
        extractedText: String?,
        merchant: String?,
        currency: String?,
        originalAmount: String?,
        discountAmount: String?,
        actualAmount: String?,
        categoryGuess: String?,
        occurredAt: String?
    ) {
        self.intent = intent
        self.action = action
        self.confidence = confidence
        self.summary = summary
        self.sourceApp = sourceApp
        self.sourceType = sourceType
        self.pageURL = pageURL
        self.extractedText = extractedText
        self.merchant = merchant
        self.currency = currency
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.actualAmount = actualAmount
        self.categoryGuess = categoryGuess
        self.occurredAt = occurredAt
    }
}

public struct LedgerEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let merchant: String?
    public let currency: String?
    public let originalAmount: String?
    public let discountAmount: String
    public let actualAmount: String
    public let category: String?
    public let occurredAt: String?
    public let intent: String
    public let sourceImagePath: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case merchant
        case currency
        case originalAmount = "original_amount"
        case discountAmount = "discount_amount"
        case actualAmount = "actual_amount"
        case category
        case occurredAt = "occurred_at"
        case intent
        case sourceImagePath = "source_image_path"
        case createdAt = "created_at"
    }

    public init(
        id: Int,
        merchant: String?,
        currency: String?,
        originalAmount: String?,
        discountAmount: String,
        actualAmount: String,
        category: String?,
        occurredAt: String?,
        intent: String,
        sourceImagePath: String,
        createdAt: String
    ) {
        self.id = id
        self.merchant = merchant
        self.currency = currency
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.actualAmount = actualAmount
        self.category = category
        self.occurredAt = occurredAt
        self.intent = intent
        self.sourceImagePath = sourceImagePath
        self.createdAt = createdAt
    }
}

public struct TodoEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let details: String?
    public let dueAt: String?
    public let sourceApp: String?
    public let pageURL: String?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case details
        case dueAt = "due_at"
        case sourceApp = "source_app"
        case pageURL = "page_url"
        case createdAt = "created_at"
    }
}

public struct ReferenceEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let summary: String?
    public let pageURL: String?
    public let sourceApp: String?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case pageURL = "page_url"
        case sourceApp = "source_app"
        case createdAt = "created_at"
    }
}

public struct ScheduleEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let details: String?
    public let startAt: String
    public let endAt: String?
    public let sourceApp: String?
    public let pageURL: String?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case details
        case startAt = "start_at"
        case endAt = "end_at"
        case sourceApp = "source_app"
        case pageURL = "page_url"
        case createdAt = "created_at"
    }
}

public struct MobileIntakeResponse: Codable, Equatable, Sendable {
    public let intent: String
    public let confidence: Double
    public let analysis: ScreenIntentAnalysis?
    public let parsedReceipt: ScreenIntentAnalysis?
    public let ledgerEntry: LedgerEntry?
    public let todoEntry: TodoEntry?
    public let referenceEntry: ReferenceEntry?
    public let scheduleEntry: ScheduleEntry?
    public let executedAction: String?
    public let message: String

    enum CodingKeys: String, CodingKey {
        case intent
        case confidence
        case analysis
        case parsedReceipt = "parsed_receipt"
        case ledgerEntry = "ledger_entry"
        case todoEntry = "todo_entry"
        case referenceEntry = "reference_entry"
        case scheduleEntry = "schedule_entry"
        case executedAction = "executed_action"
        case message
    }

    public init(
        intent: String,
        confidence: Double,
        analysis: ScreenIntentAnalysis?,
        parsedReceipt: ScreenIntentAnalysis?,
        ledgerEntry: LedgerEntry?,
        todoEntry: TodoEntry?,
        referenceEntry: ReferenceEntry?,
        scheduleEntry: ScheduleEntry?,
        executedAction: String?,
        message: String
    ) {
        self.intent = intent
        self.confidence = confidence
        self.analysis = analysis
        self.parsedReceipt = parsedReceipt
        self.ledgerEntry = ledgerEntry
        self.todoEntry = todoEntry
        self.referenceEntry = referenceEntry
        self.scheduleEntry = scheduleEntry
        self.executedAction = executedAction
        self.message = message
    }
}

public struct MobileIntakePayload: Sendable {
    public let imageData: Data?
    public let imageFilename: String?
    public let imageContentType: String?
    public let textInput: String?
    public let pageURL: String?
    public let sourceApp: String?
    public let sourceType: String?
    public let capturedAt: String?

    public init(
        imageData: Data? = nil,
        imageFilename: String? = nil,
        imageContentType: String? = nil,
        textInput: String? = nil,
        pageURL: String? = nil,
        sourceApp: String? = nil,
        sourceType: String? = nil,
        capturedAt: String? = nil
    ) {
        self.imageData = imageData
        self.imageFilename = imageFilename
        self.imageContentType = imageContentType
        self.textInput = textInput
        self.pageURL = pageURL
        self.sourceApp = sourceApp
        self.sourceType = sourceType
        self.capturedAt = capturedAt
    }

    public var hasAtLeastOnePrimaryInput: Bool {
        imageData != nil || normalized(textInput) != nil || normalized(pageURL) != nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
