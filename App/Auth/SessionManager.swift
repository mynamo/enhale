import Foundation
import EnhaleCore

/// Owns the auth state: holds the JWT (persisted in Keychain), exposes
/// login/register/logout, and hands out an authenticated `EnhaleAPIClient`.
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var token: String?

    /// The hosted enhale backend. Single source of truth for the default URL so
    /// the app works with zero setup; overridable in Settings for local dev.
    static let defaultBackendURL = "https://enhale-backend-production.up.railway.app"

    var isAuthenticated: Bool { token != nil }

    init() {
        Self.migrateBackendURLIfNeeded()
        self.token = KeychainTokenStore.load()
    }

    /// The backend base URL, configured in Settings (defaults to the hosted
    /// enhale backend so a fresh install works with no setup).
    private var baseURL: URL? {
        let raw = UserDefaults.standard.string(forKey: "backendBaseURL") ?? Self.defaultBackendURL
        return URL(string: raw)
    }

    /// One-time: point older installs that still have the local-dev default
    /// (127.0.0.1 / localhost) at the hosted backend. The Backend URL field is no
    /// longer on the login screen, so a stored localhost value would otherwise
    /// leave the user unable to sign in. Runs once; after that a URL set in
    /// Settings (including a deliberate localhost) is respected.
    private static func migrateBackendURLIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didMigrateBackendURL_v1") else { return }
        let current = defaults.string(forKey: "backendBaseURL")
        if current == nil || current!.contains("127.0.0.1") || current!.contains("localhost") {
            defaults.set(defaultBackendURL, forKey: "backendBaseURL")
        }
        defaults.set(true, forKey: "didMigrateBackendURL_v1")
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
