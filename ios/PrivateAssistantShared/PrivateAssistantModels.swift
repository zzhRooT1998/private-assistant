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
    public let speechText: String?
    public let speechConfidence: Double?
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
        case speechText = "speech_text"
        case speechConfidence = "speech_confidence"
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
        speechText: String?,
        speechConfidence: Double?,
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
        self.speechText = speechText
        self.speechConfidence = speechConfidence
        self.merchant = merchant
        self.currency = currency
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.actualAmount = actualAmount
        self.categoryGuess = categoryGuess
        self.occurredAt = occurredAt
    }
}

public struct RankedIntentCandidate: Codable, Equatable, Sendable {
    public let intent: String
    public let confidence: Double
    public let reason: String?
    public let summary: String?
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

public enum LedgerSortBy: String, Codable, CaseIterable, Identifiable, Sendable {
    case createdAt = "created_at"
    case occurredAt = "occurred_at"
    case actualAmount = "actual_amount"
    case merchant
    case category

    public var id: String { rawValue }
}

public enum LedgerSortOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case ascending = "asc"
    case descending = "desc"

    public var id: String { rawValue }
}

public struct LedgerSearchFilters: Equatable, Sendable {
    public var query: String
    public var category: String
    public var amountMin: String
    public var amountMax: String
    public var dateFrom: Date?
    public var dateTo: Date?
    public var sortBy: LedgerSortBy
    public var sortOrder: LedgerSortOrder
    public var limit: Int

    public init(
        query: String = "",
        category: String = "",
        amountMin: String = "",
        amountMax: String = "",
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        sortBy: LedgerSortBy = .createdAt,
        sortOrder: LedgerSortOrder = .descending,
        limit: Int = 50
    ) {
        self.query = query
        self.category = category
        self.amountMin = amountMin
        self.amountMax = amountMax
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.limit = limit
    }

    public var hasActiveFilters: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !amountMin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !amountMax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        dateFrom != nil ||
        dateTo != nil ||
        sortBy != .createdAt ||
        sortOrder != .descending
    }
}

public struct LedgerEntryDetail: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let merchant: String?
    public let currency: String?
    public let originalAmount: String?
    public let discountAmount: String
    public let actualAmount: String
    public let category: String?
    public let occurredAt: String?
    public let effectiveOccurredAt: String
    public let intent: String
    public let sourceImagePath: String
    public let rawModelResponseJSON: String
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
        case effectiveOccurredAt = "effective_occurred_at"
        case intent
        case sourceImagePath = "source_image_path"
        case rawModelResponseJSON = "raw_model_response_json"
        case createdAt = "created_at"
    }
}

public struct LedgerFilterOptions: Codable, Equatable, Sendable {
    public let categories: [String]
    public let merchants: [String]
    public let sortOptions: [String]
    public let sortOrders: [String]

    public init(
        categories: [String] = [],
        merchants: [String] = [],
        sortOptions: [String] = [],
        sortOrders: [String] = []
    ) {
        self.categories = categories
        self.merchants = merchants
        self.sortOptions = sortOptions
        self.sortOrders = sortOrders
    }

    enum CodingKeys: String, CodingKey {
        case categories
        case merchants
        case sortOptions = "sort_options"
        case sortOrders = "sort_orders"
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
    public let requiresConfirmation: Bool
    public let reviewID: String?
    public let rankedIntents: [RankedIntentCandidate]
    public let confirmationReason: String?
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
        case requiresConfirmation = "requires_confirmation"
        case reviewID = "review_id"
        case rankedIntents = "ranked_intents"
        case confirmationReason = "confirmation_reason"
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
        requiresConfirmation: Bool,
        reviewID: String?,
        rankedIntents: [RankedIntentCandidate],
        confirmationReason: String?,
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
        self.requiresConfirmation = requiresConfirmation
        self.reviewID = reviewID
        self.rankedIntents = rankedIntents
        self.confirmationReason = confirmationReason
        self.message = message
    }
}

public struct IntentReview: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let imagePath: String?
    public let contentType: String?
    public let textInput: String?
    public let speechText: String?
    public let speechConfidence: Double?
    public let pageURL: String?
    public let sourceApp: String?
    public let sourceType: String?
    public let capturedAt: String?
    public let rankedIntents: [RankedIntentCandidate]
    public let status: String
    public let selectedIntent: String?
    public let confirmationReason: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case imagePath = "image_path"
        case contentType = "content_type"
        case textInput = "text_input"
        case speechText = "speech_text"
        case speechConfidence = "speech_confidence"
        case pageURL = "page_url"
        case sourceApp = "source_app"
        case sourceType = "source_type"
        case capturedAt = "captured_at"
        case rankedIntents = "ranked_intents"
        case status
        case selectedIntent = "selected_intent"
        case confirmationReason = "confirmation_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct MobileIntakePayload: Sendable {
    public let imageData: Data?
    public let imageFilename: String?
    public let imageContentType: String?
    public let textInput: String?
    public let speechText: String?
    public let speechConfidence: Double?
    public let pageURL: String?
    public let sourceApp: String?
    public let sourceType: String?
    public let capturedAt: String?

    public init(
        imageData: Data? = nil,
        imageFilename: String? = nil,
        imageContentType: String? = nil,
        textInput: String? = nil,
        speechText: String? = nil,
        speechConfidence: Double? = nil,
        pageURL: String? = nil,
        sourceApp: String? = nil,
        sourceType: String? = nil,
        capturedAt: String? = nil
    ) {
        self.imageData = imageData
        self.imageFilename = imageFilename
        self.imageContentType = imageContentType
        self.textInput = textInput
        self.speechText = speechText
        self.speechConfidence = speechConfidence
        self.pageURL = pageURL
        self.sourceApp = sourceApp
        self.sourceType = sourceType
        self.capturedAt = capturedAt
    }

    public var hasAtLeastOnePrimaryInput: Bool {
        imageData != nil || normalized(textInput) != nil || normalized(speechText) != nil || normalized(pageURL) != nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
