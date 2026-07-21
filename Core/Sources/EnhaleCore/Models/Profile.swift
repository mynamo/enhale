import Foundation

/// Profile + symptom DTOs mirroring the backend `/profile` and `/symptoms`
/// contracts. This context (age, sex, meds, supplements, smoking, family
/// history, reported symptoms) is what powers personalized investigation.

public struct UserProfile: Codable, Sendable, Equatable {
    public var birthYear: Int?
    public var sex: String?
    public var heightCm: Double?
    public var ethnicity: String?
    public var smoking: String?
    public var alcohol: String?
    public var medications: [String]
    public var supplements: [String]
    public var conditions: [String]
    public var familyHistory: String?
    public var updatedAt: Date?

    public init(
        birthYear: Int? = nil, sex: String? = nil, heightCm: Double? = nil,
        ethnicity: String? = nil, smoking: String? = nil, alcohol: String? = nil,
        medications: [String] = [], supplements: [String] = [], conditions: [String] = [],
        familyHistory: String? = nil, updatedAt: Date? = nil
    ) {
        self.birthYear = birthYear; self.sex = sex; self.heightCm = heightCm
        self.ethnicity = ethnicity; self.smoking = smoking; self.alcohol = alcohol
        self.medications = medications; self.supplements = supplements
        self.conditions = conditions; self.familyHistory = familyHistory
        self.updatedAt = updatedAt
    }
}

public struct SymptomLog: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var onset: String?        // yyyy-MM-dd
    public var severity: Int?
    public var notes: String?
    public var createdAt: Date?

    public init(id: UUID = UUID(), name: String, onset: String? = nil,
                severity: Int? = nil, notes: String? = nil, createdAt: Date? = nil) {
        self.id = id; self.name = name; self.onset = onset
        self.severity = severity; self.notes = notes; self.createdAt = createdAt
    }
}
