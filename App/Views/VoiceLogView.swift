import SwiftUI
import EnhaleCore

/// The core loop: speak *or type* what you ate → parse with the LLM → save.
///
/// Dictation fills the same editable text field you can type into, so a failed
/// or wrong transcription is always recoverable — fix the text, then log.
struct VoiceLogView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var speech = SpeechRecognizer()

    @State private var text = ""
    @State private var isParsing = false
    @State private var lastParsed: ParsedMeal?
    @State private var errorMessage: String?
    @State private var recentMeals: [ParsedMeal] = []
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Editable field — works for typing, dictation, or editing a
                    // transcription before logging.
                    TextField("What did you eat? Speak or type…", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($fieldFocused)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                    // Dictate button — fills the field above; edit afterward.
                    Button(action: toggleRecording) {
                        Label(
                            speech.isRecording ? "Stop dictation" : "Dictate",
                            systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill"
                        )
                        .foregroundStyle(speech.isRecording ? .red : .accentColor)
                    }

                    if isParsing {
                        ProgressView("Understanding…")
                    }

                    if let meal = lastParsed {
                        ParsedMealCard(meal: meal)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        fieldFocused = false
                        Task { await logMeal() }
                    } label: {
                        Text("Log meal")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)

                    recentSection
                }
                .padding()
            }
            .navigationTitle("Log a meal")
            .task { await loadRecent() }
            .toolbar {
                // Open the full meal history (History is no longer a tab).
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                            .labelStyle(.titleAndIcon)
                    }
                }
                // Clear the current entry if you change your mind before logging.
                ToolbarItem(placement: .topBarLeading) {
                    if hasEntry {
                        Button("Clear", role: .destructive) { clearEntry() }
                    }
                }
                // Dismiss the keyboard without needing a return key.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
            // Mirror live dictation into the editable field while recording.
            .onChange(of: speech.transcript) { _, newValue in
                if speech.isRecording { text = newValue }
            }
        }
    }

    /// Recent meals with a link to the full history (History is no longer a
    /// tab — it lives here now).
    @ViewBuilder private var recentSection: some View {
        if !recentMeals.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent").font(.headline)
                    .padding(.bottom, 4)

                ForEach(Array(recentMeals.prefix(4).enumerated()), id: \.element.id) { index, meal in
                    MealRow(meal: meal)
                    if index < min(recentMeals.count, 4) - 1 { Divider() }
                }
            }
            .padding(.top, 8)
        }
    }

    private func loadRecent() async {
        guard let client = session.makeClient() else { return }
        if let meals = try? await client.listMeals() {
            recentMeals = meals.sorted { $0.eatenAt > $1.eatenAt }
        }
    }

    /// True when there's something worth clearing (typed text, a live
    /// dictation, or a just-parsed meal card).
    private var hasEntry: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || lastParsed != nil
            || speech.isRecording
    }

    /// Reset the screen to its empty state. Note: this only clears the
    /// in-progress entry — meals already logged are saved server-side and stay
    /// on the History tab.
    private func clearEntry() {
        if speech.isRecording { speech.stopRecording() }
        text = ""
        lastParsed = nil
        errorMessage = nil
        fieldFocused = false
    }

    private func toggleRecording() {
        errorMessage = nil
        if speech.isRecording {
            speech.stopRecording()
            return
        }
        Task {
            guard await speech.requestAuthorization() else {
                errorMessage = "Microphone/speech permission is off — you can still type your meal above."
                return
            }
            do {
                lastParsed = nil
                try speech.startRecording()
            } catch {
                errorMessage = "Couldn't start dictation — type your meal instead. (\(error.localizedDescription))"
            }
        }
    }

    private func logMeal() async {
        // If the user is mid-dictation, capture what's there first.
        if speech.isRecording { speech.stopRecording() }

        let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        guard let client = session.makeClient() else {
            errorMessage = "Set a valid backend URL in Settings first."
            return
        }

        isParsing = true
        defer { isParsing = false }

        do {
            let meal = try await client.parseMeal(transcript: transcript)
            lastParsed = meal
            text = "" // ready for the next entry; it's persisted server-side.
            await loadRecent() // refresh the Recent list below.
        } catch EnhaleAPIClient.APIError.noFoodFound {
            errorMessage = "I didn't catch any food in that — try rephrasing?"
        } catch EnhaleAPIClient.APIError.unauthorized {
            errorMessage = "Your session expired — please sign in again."
            session.logout()
        } catch let apiError as EnhaleAPIClient.APIError {
            // Friendly text (incl. the "server waking up, retry" hint for 5xx).
            errorMessage = apiError.errorDescription
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and the Backend URL in Settings."
        }
    }
}

/// Compact summary of a parsed meal.
struct ParsedMealCard: View {
    let meal: ParsedMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meal.mealType.rawValue.capitalized)
                .font(.headline)
            ForEach(meal.items) { item in
                HStack {
                    Text(item.quantity.map { "\($0) \(item.name)" } ?? item.name)
                    Spacer()
                    if let cal = item.calories {
                        Text("\(Int(cal)) kcal").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            if meal.totalCalories > 0 {
                Divider()
                HStack {
                    Text("Total").fontWeight(.semibold)
                    Spacer()
                    Text("\(Int(meal.totalCalories)) kcal").fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
