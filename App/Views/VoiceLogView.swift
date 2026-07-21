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
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                // Editable field — works for typing, dictation, or editing a
                // transcription before logging.
                TextField("What did you eat? Speak or type…", text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                // Dictate button — fills the field above; edit afterward if needed.
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
                        .padding(.horizontal)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()

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
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Log a meal")
            // Mirror live dictation into the editable field while recording.
            .onChange(of: speech.transcript) { _, newValue in
                if speech.isRecording { text = newValue }
            }
        }
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
            text = "" // ready for the next entry; it's persisted server-side and
                      // shows up on the History tab.
        } catch EnhaleAPIClient.APIError.noFoodFound {
            errorMessage = "I didn't catch any food in that — try rephrasing?"
        } catch EnhaleAPIClient.APIError.unauthorized {
            errorMessage = "Your session expired — please sign in again."
            session.logout()
        } catch {
            errorMessage = "Couldn't reach the backend: \(error.localizedDescription)"
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
