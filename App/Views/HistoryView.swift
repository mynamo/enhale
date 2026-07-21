import SwiftUI
import EnhaleCore

/// Server-backed meal history: fetches the signed-in user's meals from the
/// backend, grouped by day. This is the source of truth (cross-device), not a
/// local cache.
struct HistoryView: View {
    @EnvironmentObject private var session: SessionManager

    @State private var meals: [ParsedMeal] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if meals.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No meals yet",
                        systemImage: "fork.knife",
                        description: Text(errorMessage ?? "Log a meal on the Log tab and it'll show up here.")
                    )
                } else {
                    List {
                        ForEach(byDay, id: \.day) { group in
                            Section {
                                ForEach(group.meals) { meal in
                                    MealRow(meal: meal)
                                }
                                .onDelete { offsets in
                                    delete(offsets.map { group.meals[$0] })
                                }
                            } header: {
                                dayHeader(group)
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("History")
            .onAppear { Task { await load() } }
        }
    }

    private func dayHeader(_ group: (day: Date, meals: [ParsedMeal])) -> some View {
        let total = Int(group.meals.reduce(0) { $0 + $1.totalCalories })
        return HStack {
            Text(group.day, format: .dateTime.weekday(.wide).month().day())
            Spacer()
            if total > 0 { Text("\(total) kcal").foregroundStyle(.secondary) }
        }
    }

    private var byDay: [(day: Date, meals: [ParsedMeal])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: meals) { cal.startOfDay(for: $0.eatenAt) }
        return groups.keys.sorted(by: >).map { day in
            (day: day, meals: groups[day]!.sorted { $0.eatenAt > $1.eatenAt })
        }
    }

    private func load() async {
        guard let client = session.makeClient() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            meals = try await client.listMeals()
            errorMessage = nil
        } catch EnhaleAPIClient.APIError.unauthorized {
            session.logout()
        } catch {
            errorMessage = "Couldn't load history: \(error.localizedDescription)"
        }
    }

    private func delete(_ toDelete: [ParsedMeal]) {
        guard let client = session.makeClient() else { return }
        let ids = toDelete.map(\.id)
        meals.removeAll { ids.contains($0.id) } // optimistic
        Task {
            for id in ids { try? await client.deleteMeal(id: id) }
            await load()
        }
    }
}

private struct MealRow: View {
    let meal: ParsedMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meal.mealType.rawValue.capitalized).font(.headline)
                Spacer()
                Text(meal.eatenAt, style: .time).foregroundStyle(.secondary).font(.caption)
            }
            Text(meal.items.map(\.name).joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
            if meal.totalCalories > 0 {
                Text("\(Int(meal.totalCalories)) kcal").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
