import SwiftUI

/// Minimal settings: point the app at the enhale backend service.
///
/// No API key here anymore — the Anthropic key lives on the backend, so it
/// never ships inside the app. Clients only need to know where the service is.
struct SettingsView: View {
    @EnvironmentObject private var session: SessionManager
    @AppStorage("backendBaseURL") private var backendBaseURL = "http://127.0.0.1:8000"

    /// The backend serves the privacy policy at `/privacy`.
    private var privacyURL: URL? {
        let base = backendBaseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/privacy")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://127.0.0.1:8000", text: $backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Backend URL")
                } footer: {
                    Text("The enhale backend service that parses meals. Use http://127.0.0.1:8000 with the simulator, or your machine's LAN address on a device (add an ATS exception for plain HTTP during development).")
                }

                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Label("Profile & health context", systemImage: "person.text.rectangle")
                    }
                } footer: {
                    Text("Your age, meds, supplements, family history, and symptoms — used to personalize insights and investigations.")
                }

                Section {
                    if let privacyURL {
                        Link(destination: privacyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                        }
                    }
                } footer: {
                    Text("What enhale collects and how it's used. We never use your health data for ads and never sell it.")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        session.logout()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
