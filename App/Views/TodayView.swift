import SwiftUI
import EnhaleCore

/// Today's logged meals, with a running calorie total.
struct TodayView: View {
    @EnvironmentObject private var store: MealStore

    private var todaysMeals: [ParsedMeal] { store.meals(on: Date()) }
    private var totalCalories: Int {
        Int(todaysMeals.reduce(0) { $0 + $1.totalCalories })
    }

    var body: some View {
        NavigationStack {
            Group {
                if todaysMeals.isEmpty {
                    ContentUnavailableView(
                        "Nothing logged yet",
                        systemImage: "fork.knife",
                        description: Text("Head to the Log tab to add your first meal.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(todaysMeals) { meal in
                                VoiceLogRow(meal: meal)
                            }
                            .onDelete { indexSet in
                                indexSet.map { todaysMeals[$0] }.forEach(store.delete)
                            }
                        } footer: {
                            if totalCalories > 0 {
                                Text("Total today: \(totalCalories) kcal")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
        }
    }
}

private struct VoiceLogRow: View {
    let meal: ParsedMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meal.mealType.rawValue.capitalized).font(.headline)
                Spacer()
                Text(meal.eatenAt, style: .time).foregroundStyle(.secondary).font(.caption)
            }
            Text(meal.items.map(\.name).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
