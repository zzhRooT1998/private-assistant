import Foundation

public enum PrivateAssistantAPIError: LocalizedError {
    case emptyPayload
    case invalidResponse
    case requestTimedOut
    case unexpectedStatus(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "Provide an image, text, or URL before sending."
        case .invalidResponse:
            return "The server response was invalid."
        case .requestTimedOut:
            return "The request timed out. The assistant may still be processing the screenshot. Try again in a moment."
        case let .unexpectedStatus(code, message):
            return "Server returned \(code): \(message)"
        }
    }
}

public final class PrivateAssistantAPIClient: @unchecked Sendable {
    private enum Timeout {
        static let request: TimeInterval = 30
        static let resource: TimeInterval = 180
        static let uploadRequest: TimeInterval = 180
    }

    private let configurationStore: ConfigurationStore
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        session: URLSession? = nil
    ) {
        self.configurationStore = configurationStore
        self.session = session ?? Self.makeSession()
        self.decoder = JSONDecoder()
    }

    public func submitMobileIntake(_ payload: MobileIntakePayload) async throws -> MobileIntakeResponse {
        let request = try makeMobileIntakeRequest(payload)

        do {
            let (data, response) = try await session.data(for: request)
            return try decode(MobileIntakeResponse.self, from: data, response: response)
        } catch let error as URLError where error.code == .timedOut {
            throw PrivateAssistantAPIError.requestTimedOut
        }
    }

    public func enqueueMobileIntake(
        _ payload: MobileIntakePayload,
        completion: (@Sendable (Result<MobileIntakeResponse, Error>) -> Void)? = nil
    ) throws {
        let request = try makeMobileIntakeRequest(payload)
        let task = session.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion?(.failure(error))
                return
            }

            guard let data, let response else {
                completion?(.failure(PrivateAssistantAPIError.invalidResponse))
                return
            }

            do {
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw PrivateAssistantAPIError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw PrivateAssistantAPIError.unexpectedStatus(code: httpResponse.statusCode, message: message)
                }
                let decoded = try decoder.decode(MobileIntakeResponse.self, from: data)
                completion?(.success(decoded))
            } catch {
                completion?(.failure(error))
            }
        }
        task.resume()
    }

    public func fetchLedger() async throws -> [LedgerEntry] {
        let endpoint = try makeURL(path: "api/ledger")
        do {
            let (data, response) = try await session.data(from: endpoint)
            return try decode([LedgerEntry].self, from: data, response: response)
        } catch let error as URLError where error.code == .timedOut {
            throw PrivateAssistantAPIError.requestTimedOut
        }
    }

    public func fetchTodos() async throws -> [TodoEntry] {
        let endpoint = try makeURL(path: "api/todos")
        do {
            let (data, response) = try await session.data(from: endpoint)
            return try decode([TodoEntry].self, from: data, response: response)
        } catch let error as URLError where error.code == .timedOut {
            throw PrivateAssistantAPIError.requestTimedOut
        }
    }

    public func fetchReferences() async throws -> [ReferenceEntry] {
        let endpoint = try makeURL(path: "api/references")
        do {
            let (data, response) = try await session.data(from: endpoint)
            return try decode([ReferenceEntry].self, from: data, response: response)
        } catch let error as URLError where error.code == .timedOut {
            throw PrivateAssistantAPIError.requestTimedOut
        }
    }

    public func fetchSchedules() async throws -> [ScheduleEntry] {
        let endpoint = try makeURL(path: "api/schedules")
        do {
            let (data, response) = try await session.data(from: endpoint)
            return try decode([ScheduleEntry].self, from: data, response: response)
        } catch let error as URLError where error.code == .timedOut {
            throw PrivateAssistantAPIError.requestTimedOut
        }
    }

    public func fetchPendingIntentReviews(limit: Int = 10) async throws -> [IntentReview] {
        let endpoint = try makeURL(path: "api/intent-reviews?status=pending&limit=\(limit)")
        do {
            let (data, response) = try await session.data(from: endpoint)
            return try decode([IntentReview].self, from: data, response: response)
        } catch let error as URLError where error.code == .timedOut {
            throw PrivateAssistantAPIError.requestTimedOut
        }
    }

    public func confirmIntentReview(
        reviewID: String,
        selectedIntent: String? = nil,
        customIntent: String? = nil
    ) async throws -> MobileIntakeResponse {
        let endpoint = try makeURL(path: "agent/life/mobile-intake/\(reviewID)/confirm")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Timeout.uploadRequest
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ConfirmIntentPayload(selectedIntent: selectedIntent, customIntent: customIntent)
        )

        do {
            let (data, response) = try await session.data(for: request)
            return try decode(MobileIntakeResponse.self, from: data, response: response)
        } catch let error as URLError where error.code == .timedOut {
            throw PrivateAssistantAPIError.requestTimedOut
        }
    }

    private func makeURL(path: String) throws -> URL {
        let base = try configurationStore.loadBaseURL().absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/\(path)")!
    }

    private func makeMobileIntakeRequest(_ payload: MobileIntakePayload) throws -> URLRequest {
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
        request.timeoutInterval = Timeout.uploadRequest
        request.setValue(multipart.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.encoded()
        return request
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Timeout.request
        configuration.timeoutIntervalForResource = Timeout.resource
        return URLSession(configuration: configuration)
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

private struct ConfirmIntentPayload: Encodable {
    let selectedIntent: String?
    let customIntent: String?

    enum CodingKeys: String, CodingKey {
        case selectedIntent = "selected_intent"
        case customIntent = "custom_intent"
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
