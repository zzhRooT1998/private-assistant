import Foundation

public enum PrivateAssistantAPIError: LocalizedError {
    case emptyPayload
    case invalidResponse
    case unexpectedStatus(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "Provide an image, text, or URL before sending."
        case .invalidResponse:
            return "The server response was invalid."
        case let .unexpectedStatus(code, message):
            return "Server returned \(code): \(message)"
        }
    }
}

public final class PrivateAssistantAPIClient: @unchecked Sendable {
    private let configurationStore: ConfigurationStore
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        session: URLSession = .shared
    ) {
        self.configurationStore = configurationStore
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func submitMobileIntake(_ payload: MobileIntakePayload) async throws -> MobileIntakeResponse {
        guard payload.hasAtLeastOnePrimaryInput else {
            throw PrivateAssistantAPIError.emptyPayload
        }

        let endpoint = try makeURL(path: "agent/life/mobile-intake")
        let multipart = MultipartFormData()
        multipart.addField(named: "text_input", value: payload.textInput)
        multipart.addField(named: "page_url", value: payload.pageURL)
        multipart.addField(named: "source_app", value: payload.sourceApp)
        multipart.addField(named: "source_type", value: payload.sourceType)
        multipart.addField(named: "captured_at", value: payload.capturedAt)
        multipart.addFile(
            named: "image",
            filename: payload.imageFilename,
            contentType: payload.imageContentType,
            data: payload.imageData
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(multipart.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.encoded()

        let (data, response) = try await session.data(for: request)
        return try decode(MobileIntakeResponse.self, from: data, response: response)
    }

    public func fetchLedger() async throws -> [LedgerEntry] {
        let endpoint = try makeURL(path: "api/ledger")
        let (data, response) = try await session.data(from: endpoint)
        return try decode([LedgerEntry].self, from: data, response: response)
    }

    public func fetchTodos() async throws -> [TodoEntry] {
        let endpoint = try makeURL(path: "api/todos")
        let (data, response) = try await session.data(from: endpoint)
        return try decode([TodoEntry].self, from: data, response: response)
    }

    public func fetchReferences() async throws -> [ReferenceEntry] {
        let endpoint = try makeURL(path: "api/references")
        let (data, response) = try await session.data(from: endpoint)
        return try decode([ReferenceEntry].self, from: data, response: response)
    }

    public func fetchSchedules() async throws -> [ScheduleEntry] {
        let endpoint = try makeURL(path: "api/schedules")
        let (data, response) = try await session.data(from: endpoint)
        return try decode([ScheduleEntry].self, from: data, response: response)
    }

    private func makeURL(path: String) throws -> URL {
        let base = try configurationStore.loadBaseURL().absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/\(path)")!
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: URLResponse) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PrivateAssistantAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PrivateAssistantAPIError.unexpectedStatus(code: httpResponse.statusCode, message: message)
        }
        return try decoder.decode(T.self, from: data)
    }
}

private final class MultipartFormData {
    private let boundary = "Boundary-\(UUID().uuidString)"
    private var body = Data()

    var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    func addField(named name: String, value: String?) {
        guard let value = normalized(value) else { return }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    func addFile(named name: String, filename: String?, contentType: String?, data: Data?) {
        guard let data else { return }
        let resolvedFilename = normalized(filename) ?? "capture.jpg"
        let resolvedContentType = normalized(contentType) ?? "image/jpeg"

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(resolvedFilename)\"\r\n")
        append("Content-Type: \(resolvedContentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    func encoded() -> Data {
        var data = body
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private func append(_ string: String) {
        body.append(string.data(using: .utf8)!)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
