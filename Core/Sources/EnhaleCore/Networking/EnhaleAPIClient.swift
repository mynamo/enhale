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

    /// Delete one of the signed-in user's meals.
    public func deleteMeal(id: UUID) async throws {
        _ = try await send(
            path: "meals/\(id.uuidString.lowercased())", method: "DELETE",
            body: Optional<Empty>.none, authorized: true
        )
    }

    // MARK: - Health

    /// Push HealthKit-derived data to the backend (idempotent upsert).
    @discardableResult
    public func syncHealth(_ request: HealthSyncRequest) async throws -> HealthSyncResult {
        let data = try await send(path: "health/sync", method: "POST", body: request, authorized: true)
        return try Self.decoder.decode(HealthSyncResult.self, from: data)
    }

    /// Read back a recent health summary for the signed-in user.
    public func healthSummary(days: Int = 14) async throws -> HealthSummary {
        let data = try await send(
            path: "health/summary?days=\(days)", method: "GET",
            body: Optional<Empty>.none, authorized: true
        )
        return try Self.decoder.decode(HealthSummary.self, from: data)
    }

    // MARK: - Blood work

    /// Upload a lab report (PDF/PNG/JPEG). The backend extracts markers via
    /// Claude and returns the structured panel; the file itself isn't stored.
    public func uploadBloodWork(
        fileData: Data, filename: String, mimeType: String
    ) async throws -> BloodWorkPanel {
        guard let token else { throw APIError.unauthorized }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("bloodwork/upload"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let ok = try Self.process(data, response)
        return try Self.decoder.decode(BloodWorkPanel.self, from: ok)
    }

    /// List the signed-in user's uploaded blood work panels.
    public func listBloodWork() async throws -> [BloodWorkPanel] {
        let data = try await send(path: "bloodwork", method: "GET", body: Optional<Empty>.none, authorized: true)
        return try Self.decoder.decode([BloodWorkPanel].self, from: data)
    }

    /// Delete one blood work panel.
    public func deleteBloodWork(id: UUID) async throws {
        _ = try await send(
            path: "bloodwork/\(id.uuidString.lowercased())", method: "DELETE",
            body: Optional<Empty>.none, authorized: true
        )
    }

    // MARK: - Insights

    /// Generate a fresh recommendations report from the user's data (LLM call —
    /// can take some seconds). Also stored server-side.
    public func generateInsights() async throws -> InsightReport {
        let data = try await send(path: "insights/generate", method: "POST", body: Optional<Empty>.none, authorized: true)
        return try Self.decoder.decode(InsightReport.self, from: data)
    }

    /// List previously generated reports, newest first.
    public func listInsights() async throws -> [InsightReport] {
        let data = try await send(path: "insights", method: "GET", body: Optional<Empty>.none, authorized: true)
        return try Self.decoder.decode([InsightReport].self, from: data)
    }

    // MARK: - Profile & symptoms

    public func getProfile() async throws -> UserProfile {
        let data = try await send(path: "profile", method: "GET", body: Optional<Empty>.none, authorized: true)
        return try Self.decoder.decode(UserProfile.self, from: data)
    }

    @discardableResult
    public func putProfile(_ profile: UserProfile) async throws -> UserProfile {
        let data = try await send(path: "profile", method: "PUT", body: profile, authorized: true)
        return try Self.decoder.decode(UserProfile.self, from: data)
    }

    public func listSymptoms() async throws -> [SymptomLog] {
        let data = try await send(path: "symptoms", method: "GET", body: Optional<Empty>.none, authorized: true)
        return try Self.decoder.decode([SymptomLog].self, from: data)
    }

    @discardableResult
    public func addSymptom(_ symptom: SymptomLog) async throws -> SymptomLog {
        let data = try await send(path: "symptoms", method: "POST", body: symptom, authorized: true)
        return try Self.decoder.decode(SymptomLog.self, from: data)
    }

    public func deleteSymptom(id: UUID) async throws {
        _ = try await send(
            path: "symptoms/\(id.uuidString.lowercased())", method: "DELETE",
            body: Optional<Empty>.none, authorized: true
        )
    }

    // MARK: - Investigation ("Ask enhale")

    /// Investigate a concern against the user's whole dataset (LLM call).
    public func investigate(concern: String) async throws -> InvestigationReport {
        let data = try await send(
            path: "investigate", method: "POST",
            body: InvestigateRequest(concern: concern), authorized: true
        )
        return try Self.decoder.decode(InvestigationReport.self, from: data)
    }

    public func listInvestigations() async throws -> [InvestigationReport] {
        let data = try await send(path: "investigate", method: "GET", body: Optional<Empty>.none, authorized: true)
        return try Self.decoder.decode([InvestigationReport].self, from: data)
    }

    private struct InvestigateRequest: Encodable { let concern: String }

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
        return try Self.process(data, response)
    }

    /// Map an HTTP response to data-or-error. Shared by JSON and multipart calls.
    private static func process(_ data: Data, _ response: URLResponse) throws -> Data {
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
            // Safety net: a datetime with no timezone (e.g. SQLite round-trips) —
            // interpret it as UTC.
            let naive = DateFormatter()
            naive.calendar = Calendar(identifier: .gregorian)
            naive.timeZone = TimeZone(identifier: "UTC")
            naive.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = naive.date(from: string) { return date }
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
