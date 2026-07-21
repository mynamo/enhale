import Foundation

/// Insights DTOs mirroring the backend `/insights` contract — recommendations
/// synthesized from meals + health + blood work.

public struct Recommendation: Codable, Identifiable, Sendable, Equatable {
    public var title: String
    public var detail: String
    public var category: String    // nutrition | activity | sleep | labs | general
    public var priority: String    // high | medium | low
    public var rationale: String

    public var id: String { title }
}

public struct InsightReport: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var generatedAt: Date?
    public var summary: String
    public var observations: [String]
    public var recommendations: [Recommendation]
    public var disclaimer: String
}
