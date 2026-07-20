import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin client for the enhale backend service.
///
/// All the reusable logic — LLM parsing, prompts, persistence, the API key —
/// lives in the backend. This client marshals requests and decodes responses.
/// The web and Android apps will have their own equivalent, all conforming to
/// the same HTTP contract.
public struct EnhaleAPIClient: Sendable {
    private let baseURL: URL
    private let token: String?
    private let session: URLSession

    /// - Parameter token: JWT from `register`/`login`. Nil for the auth calls
    ///   themselves; required for `/meals` calls.
    public init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public enum APIError: Error {
        case http(status: Int, body: String)
        case unauthorized
        case emailTaken
        case noFoodFound
        case badResponse
    }

    // MARK: - Auth

    /// Register a new account; returns a JWT access token.
    public func register(email: String, password: String) async throws -> String {
        try await authCall(path: "auth/register", email: email, password: password, taken: true)
    }

    /// Log in; returns a JWT access token.
    public func login(email: String, password: String) async throws -> String {
        try await authCall(path: "auth/login", email: email, password: password, taken: false)
    }

    private func authCall(path: String, email: String, password: String, taken: Bool) async throws -> String {
        let data = try await send(
            path: path,
            method: "POST",
            body: Credentials(email: email, password: password),
            authorized: false
        )
        return try Self.decoder.decode(TokenResponse.self, from: data).accessToken
    }

    // MARK: - Meals

    /// Parse a spoken transcript into a structured meal and persist it server-side.
    public func parseMeal(
        transcript: String,
        now: Date? = nil,
        timeZone: TimeZone = .current
    ) async throws -> ParsedMeal {
        let data = try await send(
            path: "meals/parse",
            method: "POST",
            body: ParseMealRequest(transcript: transcript, now: now, timezone: timeZone.identifier),
            authorized: true
        )
        return try Self.decoder.decode(ParsedMeal.self, from: data)
    }

    /// List the signed-in user's meals; pass `day` to filter to one calendar day.
    public func listMeals(on day: Date? = nil) async throws -> [ParsedMeal] {
        var path = "meals"
        if let day {
            path += "?on=\(Self.dayFormatter.string(from: day))"
        }
        let data = try await send(path: path, method: "GET", body: Optional<Empty>.none, authorized: true)
        return try Self.decoder.decode([ParsedMeal].self, from: data)
    }

    // MARK: - Request plumbing

    private func send<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        authorized: Bool
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }
        if authorized {
            guard let token else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        case 409:
            throw APIError.emailTaken
        case 422:
            throw APIError.noFoodFound
        default:
            throw APIError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            )
        }
    }

    // MARK: - Wire types

    private struct Credentials: Encodable { let email: String; let password: String }
    private struct TokenResponse: Decodable { let accessToken: String }
    private struct ParseMealRequest: Encodable {
        let transcript: String
        let now: Date?
        let timezone: String
    }
    /// Placeholder body type for GET requests (no body encoded).
    private struct Empty: Encodable {}

    // MARK: - Coders

    // Computed (not `static let`) so they stay concurrency-safe under Swift 6 —
    // JSONEncoder/JSONDecoder are non-Sendable classes.
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // Pydantic may or may not include fractional seconds — accept both.
        d.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: string) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unrecognized date: \(string)")
            )
        }
        return d
    }

    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }
}
