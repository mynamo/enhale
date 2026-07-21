import Foundation

/// "Ask enhale" investigation DTOs — ranked root-cause hypotheses plus the
/// data gaps needed to narrow things down. Mirrors the backend `/investigate`
/// contract.

public struct Hypothesis: Codable, Identifiable, Sendable, Equatable {
    public var title: String
    public var likelihood: String     // high | medium | low
    public var rationale: String
    public var supporting: [String]
    public var missing: [String]

    public var id: String { title }
}

public struct DataGap: Codable, Identifiable, Sendable, Equatable {
    public var item: String
    public var why: String
    public var howToGet: String

    public var id: String { item }
}

public struct InvestigationReport: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var concern: String
    public var generatedAt: Date?
    public var summary: String
    public var hypotheses: [Hypothesis]
    public var dataGaps: [DataGap]
    public var nextSteps: [String]
    public var disclaimer: String
}
