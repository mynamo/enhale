import SwiftUI

/// Minimal settings: point the app at the enhale backend service.
///
/// No API key here anymore — the Anthropic key lives on the backend, so it
/// never ships inside the app. Clients only need to know where the service is.
struct SettingsView: View {
    @EnvironmentObject private var session: SessionManager
    @AppStorage("backendBaseURL") private var backendBaseURL = "http://localhost:8000"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://localhost:8000", text: $backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Backend URL")
                } footer: {
                    Text("The enhale backend service that parses meals. Use http://localhost:8000 with the simulator, or your machine's LAN address on a device (add an ATS exception for plain HTTP during development).")
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
