import Foundation

/// A single food or drink within a meal, with a rough nutrition estimate.
///
/// All nutrition fields are optional: when the user says "a handful of almonds"
/// the LLM can estimate, but when it genuinely can't it should leave fields nil
/// rather than fabricate numbers. `estimated` marks that these came from a model
/// guess, not a label the user read out.
public struct FoodItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Normalized food name, e.g. "scrambled eggs".
    public var name: String
    /// Free-text portion as the user described it, e.g. "two", "a large bowl".
    public var quantity: String?

    public var calories: Double?
    public var proteinGrams: Double?
    public var carbGrams: Double?
    public var fatGrams: Double?

    /// True when the nutrition numbers are model estimates rather than user-stated.
    public var estimated: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: String? = nil,
        calories: Double? = nil,
        proteinGrams: Double? = nil,
        carbGrams: Double? = nil,
        fatGrams: Double? = nil,
        estimated: Bool = true
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
        self.estimated = estimated
    }
}
