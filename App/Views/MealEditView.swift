import SwiftUI
import EnhaleCore

/// Edit a previously logged meal — change its type, time, and items. Micronutrient
/// detail the phone doesn't display is preserved server-side on save (the backend
/// merges by item id).
struct MealEditView: View {
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var meal: ParsedMeal
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Called after a successful save so the caller can refresh its list.
    let onSaved: () async -> Void

    init(meal: ParsedMeal, onSaved: @escaping () async -> Void) {
        _meal = State(initialValue: meal)
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section {
                Picker("Meal", selection: $meal.mealType) {
                    ForEach(MealType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                DatePicker("When", selection: $meal.eatenAt)
            }

            Section("Items") {
                ForEach($meal.items) { $item in
                    itemEditor($item)
                }
                .onDelete { meal.items.remove(atOffsets: $0) }

                Button {
                    meal.items.append(FoodItem(name: "", estimated: false))
                } label: {
                    Label("Add item", systemImage: "plus")
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("Edit meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || !hasValidItem)
            }
        }
        .overlay { if isSaving { ProgressView() } }
    }

    @ViewBuilder private func itemEditor(_ item: Binding<FoodItem>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Food name", text: item.name)
                .font(.headline)
            TextField("Quantity (e.g. 1 cup)", text: optString(item.quantity))
                .font(.subheadline)
            HStack(spacing: 12) {
                numberField("Cal", optDouble(item.calories))
                numberField("Protein", optDouble(item.proteinGrams))
                numberField("Carbs", optDouble(item.carbGrams))
                numberField("Fat", optDouble(item.fatGrams))
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func numberField(_ label: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            TextField("—", text: value)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var hasValidItem: Bool {
        meal.items.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func save() async {
        guard let client = session.makeClient() else {
            errorMessage = "Set a valid backend URL first."; return
        }
        var cleaned = meal
        cleaned.items = meal.items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            _ = try await client.updateMeal(cleaned)
            await onSaved()
            dismiss()
        } catch EnhaleAPIClient.APIError.unauthorized {
            session.logout()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    // MARK: - Optional-field bindings

    private func optString(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func optDouble(_ binding: Binding<Double?>) -> Binding<String> {
        Binding(
            get: {
                guard let v = binding.wrappedValue else { return "" }
                return v == v.rounded() ? String(Int(v)) : String(v)
            },
            set: { binding.wrappedValue = Double($0) }  // empty / invalid → nil
        )
    }
}
