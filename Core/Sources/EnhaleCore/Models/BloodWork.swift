import Foundation

/// Blood work DTOs mirroring the backend `/bloodwork` contract. `collectedOn`
/// is an ISO `yyyy-MM-dd` string (date-only, like other calendar-date fields).

public struct BloodMarker: Codable, Identifiable, Sendable, Equatable {
    public var name: String
    public var value: String            // raw value as printed
    public var valueNum: Double?        // numeric parse when applicable
    public var unit: String?
    public var referenceRange: String?
    public var flag: String?            // "high" | "low" | "normal" | nil

    public var id: String { name }

    public var isOutOfRange: Bool { flag == "high" || flag == "low" }
}

public struct BloodWorkPanel: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var collectedOn: String?     // yyyy-MM-dd
    public var sourceFilename: String
    public var markers: [BloodMarker]
    public var note: String?
    public var createdAt: Date?

    public var outOfRangeCount: Int { markers.filter(\.isOutOfRange).count }
}
