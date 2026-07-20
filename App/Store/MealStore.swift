import Foundation
import EnhaleCore

/// Holds logged meals and persists them to a JSON file in Application Support.
///
/// This is intentionally simple for the MVP. When the data model grows (blood
/// work, HealthKit correlations), migrate to SwiftData / Core Data — see
/// [[enhale-project]].
@MainActor
final class MealStore: ObservableObject {
    @Published private(set) var meals: [ParsedMeal] = []

    private let fileURL: URL

    init(filename: String = "meals.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(filename)
        load()
    }

    func add(_ meal: ParsedMeal) {
        meals.insert(meal, at: 0) // newest first
        save()
    }

    func delete(_ meal: ParsedMeal) {
        meals.removeAll { $0.id == meal.id }
        save()
    }

    /// Meals eaten on the same calendar day as `date`, in time order.
    func meals(on date: Date, calendar: Calendar = .current) -> [ParsedMeal] {
        meals
            .filter { calendar.isDate($0.eatenAt, inSameDayAs: date) }
            .sorted { $0.eatenAt < $1.eatenAt }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        meals = (try? JSONDecoder().decode([ParsedMeal].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(meals) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
