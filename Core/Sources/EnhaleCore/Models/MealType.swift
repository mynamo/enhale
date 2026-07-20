import Foundation

/// Which eating occasion a logged item belongs to.
///
/// `unspecified` is the safe default when the user didn't say and the time of
/// day is ambiguous — the parser should never *guess* a meal type with false
/// confidence.
public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
    case unspecified

    /// A reasonable default derived purely from a wall-clock hour, used only
    /// when the transcript gives no explicit signal.
    public static func inferred(fromHour hour: Int) -> MealType {
        switch hour {
        case 5..<11:  return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default:      return .snack
        }
    }
}
