import Foundation
import EnhaleCore

/// Owns the auth state: holds the JWT (persisted in Keychain), exposes
/// login/register/logout, and hands out an authenticated `EnhaleAPIClient`.
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var token: String?

    var isAuthenticated: Bool { token != nil }

    init() {
        self.token = KeychainTokenStore.load()
    }

    /// The backend base URL, configured in Settings (defaults to localhost).
    private var baseURL: URL? {
        let raw = UserDefaults.standard.string(forKey: "backendBaseURL") ?? "http://localhost:8000"
        return URL(string: raw)
    }

    /// An API client carrying the current token (nil until signed in).
    func makeClient() -> EnhaleAPIClient? {
        guard let baseURL else { return nil }
        return EnhaleAPIClient(baseURL: baseURL, token: token)
    }

    func register(email: String, password: String) async throws {
        guard let baseURL else { throw SessionError.noBackendURL }
        let client = EnhaleAPIClient(baseURL: baseURL)
        try store(await client.register(email: email, password: password))
    }

    func login(email: String, password: String) async throws {
        guard let baseURL else { throw SessionError.noBackendURL }
        let client = EnhaleAPIClient(baseURL: baseURL)
        try store(await client.login(email: email, password: password))
    }

    func logout() {
        KeychainTokenStore.clear()
        token = nil
    }

    private func store(_ newToken: String) {
        KeychainTokenStore.save(newToken)
        token = newToken
    }

    enum SessionError: LocalizedError {
        case noBackendURL
        var errorDescription: String? {
            "Set a valid backend URL in Settings first."
        }
    }
}
