import Foundation

/// The structured result of parsing one spoken log entry.
///
/// Example: "I had two scrambled eggs and a coffee around 8 this morning"
/// becomes a `ParsedMeal` with two `FoodItem`s, `mealType == .breakfast`, and
/// `eatenAt` resolved to 8am today relative to the capture time.
public struct ParsedMeal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var items: [FoodItem]
    public var mealType: MealType
    /// When the food was *eaten* — resolved from relative phrases ("an hour
    /// ago") against the moment of capture.
    public var eatenAt: Date
    /// The verbatim speech transcript this was parsed from, kept for audit and
    /// re-parsing if the model improves.
    public var rawTranscript: String
    /// 0.0–1.0 model confidence that the parse faithfully reflects the speech.
    public var confidence: Double

    public init(
        id: UUID = UUID(),
        items: [FoodItem],
        mealType: MealType,
        eatenAt: Date,
        rawTranscript: String,
        confidence: Double
    ) {
        self.id = id
        self.items = items
        self.mealType = mealType
        self.eatenAt = eatenAt
        self.rawTranscript = rawTranscript
        self.confidence = confidence
    }

    /// Sum of per-item calories, ignoring items where it's unknown.
    public var totalCalories: Double {
        items.compactMap(\.calories).reduce(0, +)
    }
}
