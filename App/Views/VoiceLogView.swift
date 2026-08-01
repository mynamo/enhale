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
    @State private var errorMessage: String?
    /// The text already in the field when a dictation session starts; live
    /// transcript is appended to this so starting/resuming dictation never wipes
    /// what's already there.
    @State private var dictationBase = ""
    @State private var showSuccess = false
    @State private var showFailure = false
    @State private var failureMessage = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)

                // Editable field — works for typing, dictation, or editing a
                // transcription before logging.
                TextField("What did you eat? Speak or type…", text: $text, axis: .vertical)
                    .lineLimit(2...6)
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

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
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
            }
            .padding()
            // History lives behind a button pinned to the bottom of the screen.
            .safeAreaInset(edge: .bottom) {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Log a meal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EnhaleLogo() }
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
            // Append live dictation after any existing text (don't overwrite it).
            .onChange(of: speech.transcript) { _, newValue in
                guard speech.isRecording else { return }
                if newValue.isEmpty {
                    text = dictationBase
                } else if dictationBase.isEmpty {
                    text = newValue
                } else {
                    text = dictationBase + " " + newValue
                }
            }
            .alert("Meal logged successfully", isPresented: $showSuccess) {
                Button("Log another meal") { text = ""; fieldFocused = true }
                Button("Done", role: .cancel) { fieldFocused = false }
            } message: {
                Text("It's been added to your history.")
            }
            .alert("Meal logging failed", isPresented: $showFailure) {
                Button("Try again") { Task { await logMeal() } }
                Button("Done", role: .cancel) { }
            } message: {
                Text(failureMessage)
            }
        }
    }

    /// True when there's something worth clearing (typed text or a live
    /// dictation in progress).
    private var hasEntry: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || speech.isRecording
    }

    /// Reset the screen to its empty state. Note: this only clears the
    /// in-progress entry — meals already logged are saved server-side and stay
    /// in your history.
    private func clearEntry() {
        if speech.isRecording { speech.stopRecording() }
        text = ""
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
                // Preserve whatever's already typed/dictated; the next
                // transcript is appended to it.
                dictationBase = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            failureMessage = "Set a valid backend URL in Settings first."
            showFailure = true
            return
        }

        isParsing = true
        defer { isParsing = false }

        do {
            _ = try await client.parseMeal(transcript: transcript)
            text = ""            // saved server-side; ready for the next entry
            fieldFocused = false
            showSuccess = true
        } catch EnhaleAPIClient.APIError.noFoodFound {
            failureMessage = "I didn't catch any food in that — try rephrasing?"
            showFailure = true
        } catch EnhaleAPIClient.APIError.unauthorized {
            session.logout()     // returns to the sign-in screen; no alert needed
        } catch let apiError as EnhaleAPIClient.APIError {
            // Friendly text (incl. the "server waking up, retry" hint for 5xx).
            failureMessage = apiError.errorDescription ?? "Something went wrong."
            showFailure = true
        } catch {
            failureMessage = "Couldn't reach the server — check your connection and the Backend URL in Settings."
            showFailure = true
        }
    }
}
