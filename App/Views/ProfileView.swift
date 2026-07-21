import SwiftUI
import EnhaleCore

/// Profile + symptoms — the context that makes investigation personal.
/// Reached from Settings.
struct ProfileView: View {
    @EnvironmentObject private var session: SessionManager

    @State private var birthYear = ""
    @State private var sex = "unspecified"
    @State private var heightCm = ""
    @State private var smoking = "unset"
    @State private var alcohol = "unset"
    @State private var medications = ""
    @State private var supplements = ""
    @State private var conditions = ""
    @State private var familyHistory = ""

    @State private var symptoms: [SymptomLog] = []
    @State private var newSymptom = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("About you") {
                LabeledContent("Birth year") {
                    TextField("1990", text: $birthYear).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                Picker("Sex", selection: $sex) {
                    ForEach(["unspecified", "female", "male", "other"], id: \.self) { Text($0.capitalized) }
                }
                LabeledContent("Height (cm)") {
                    TextField("170", text: $heightCm).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }

            Section("Lifestyle") {
                Picker("Smoking", selection: $smoking) {
                    ForEach(["unset", "never", "former", "current"], id: \.self) { Text($0.capitalized) }
                }
                Picker("Alcohol", selection: $alcohol) {
                    ForEach(["unset", "none", "occasional", "moderate", "heavy"], id: \.self) { Text($0.capitalized) }
                }
            }

            Section {
                TextField("Medications (comma-separated)", text: $medications, axis: .vertical)
                TextField("Supplements (comma-separated)", text: $supplements, axis: .vertical)
                TextField("Known conditions (comma-separated)", text: $conditions, axis: .vertical)
                TextField("Family history", text: $familyHistory, axis: .vertical)
            } header: {
                Text("Health context")
            } footer: {
                Text("Meds, supplements, and family history are key to accurate insights — they're common confounders.")
            }

            Section("Symptoms & concerns") {
                ForEach(symptoms) { s in
                    HStack {
                        Text(s.name)
                        Spacer()
                        if let sev = s.severity { Text("\(sev)/5").foregroundStyle(.secondary).font(.caption) }
                    }
                }
                .onDelete(perform: deleteSymptom)
                HStack {
                    TextField("Add a concern (e.g. grey hair)", text: $newSymptom)
                    Button("Add") { Task { await addSymptom() } }
                        .disabled(newSymptom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Button("Save profile") { Task { await save() } }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await load() } }
        .alert("Saved", isPresented: $saved) { Button("OK", role: .cancel) {} }
    }

    private func load() async {
        guard let client = session.makeClient() else { return }
        if let p = try? await client.getProfile() {
            birthYear = p.birthYear.map(String.init) ?? ""
            sex = p.sex ?? "unspecified"
            heightCm = p.heightCm.map { String(Int($0)) } ?? ""
            smoking = p.smoking ?? "unset"
            alcohol = p.alcohol ?? "unset"
            medications = p.medications.joined(separator: ", ")
            supplements = p.supplements.joined(separator: ", ")
            conditions = p.conditions.joined(separator: ", ")
            familyHistory = p.familyHistory ?? ""
        }
        symptoms = (try? await client.listSymptoms()) ?? []
    }

    private func save() async {
        guard let client = session.makeClient() else { return }
        let profile = UserProfile(
            birthYear: Int(birthYear),
            sex: sex == "unspecified" ? nil : sex,
            heightCm: Double(heightCm),
            smoking: smoking == "unset" ? nil : smoking,
            alcohol: alcohol == "unset" ? nil : alcohol,
            medications: splitList(medications),
            supplements: splitList(supplements),
            conditions: splitList(conditions),
            familyHistory: familyHistory.isEmpty ? nil : familyHistory
        )
        if (try? await client.putProfile(profile)) != nil { saved = true }
    }

    private func addSymptom() async {
        guard let client = session.makeClient() else { return }
        let name = newSymptom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newSymptom = ""
        _ = try? await client.addSymptom(SymptomLog(name: name))
        symptoms = (try? await client.listSymptoms()) ?? symptoms
    }

    private func deleteSymptom(_ offsets: IndexSet) {
        guard let client = session.makeClient() else { return }
        let ids = offsets.map { symptoms[$0].id }
        symptoms.remove(atOffsets: offsets)
        Task { for id in ids { try? await client.deleteSymptom(id: id) } }
    }

    private func splitList(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
