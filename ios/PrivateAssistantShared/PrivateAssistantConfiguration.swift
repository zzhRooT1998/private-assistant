import Foundation

public enum PrivateAssistantEnvironment {
    public static let serverBaseURLKey = "server_base_url"
    public static let defaultServerBaseURL = "https://b308-112-10-191-85.ngrok-free.app"
}

public enum ConfigurationStoreError: LocalizedError {
    case invalidBaseURL(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value):
            return "Invalid server URL: \(value)"
        }
    }
}

public final class ConfigurationStore: @unchecked Sendable {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults? = nil) {
        self.userDefaults = userDefaults ?? .standard
    }

    public func loadBaseURLString() -> String {
        if let saved = userDefaults.string(forKey: PrivateAssistantEnvironment.serverBaseURLKey) {
            return saved
        }
        return PrivateAssistantEnvironment.defaultServerBaseURL
    }

    public func saveBaseURLString(_ value: String) {
        userDefaults.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: PrivateAssistantEnvironment.serverBaseURLKey)
    }

    public func loadBaseURL() throws -> URL {
        let rawValue = loadBaseURLString()
        guard let url = URL(string: rawValue), url.scheme != nil else {
            throw ConfigurationStoreError.invalidBaseURL(rawValue)
        }
        return url
    }
}
