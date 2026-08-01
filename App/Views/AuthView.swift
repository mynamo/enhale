import SwiftUI
import EnhaleCore

/// Sign-in / sign-up screen shown until the user has a valid session.
///
/// The app ships pointed at the hosted enhale backend, so there's nothing to
/// configure here. The Backend URL override lives in Settings (behind login) for
/// local development.
struct AuthView: View {
    @EnvironmentObject private var session: SessionManager
    @AppStorage("backendBaseURL") private var backendBaseURL = SessionManager.defaultBackendURL

    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(isRegistering ? .newPassword : .password)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }

                Section {
                    Button(isRegistering ? "Create account" : "Sign in") {
                        Task { await submit() }
                    }
                    .disabled(isBusy || email.isEmpty || password.isEmpty)

                    Button(isRegistering ? "Have an account? Sign in" : "New here? Create an account") {
                        isRegistering.toggle()
                        errorMessage = nil
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle(isRegistering ? "Create account" : "Welcome to enhale")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EnhaleLogo() }
            }
            .overlay { if isBusy { ProgressView() } }
        }
    }

    private func submit() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            if isRegistering {
                try await session.register(email: email, password: password)
            } else {
                try await session.login(email: email, password: password)
            }
        } catch EnhaleAPIClient.APIError.emailTaken {
            errorMessage = "That email is already registered — try signing in."
        } catch EnhaleAPIClient.APIError.unauthorized {
            errorMessage = "Incorrect email or password."
        } catch let EnhaleAPIClient.APIError.http(status, _) {
            errorMessage = "The server at \(backendBaseURL) responded with HTTP \(status). Check the Backend URL points at the enhale backend."
        } catch EnhaleAPIClient.APIError.badResponse {
            errorMessage = "Unexpected response from \(backendBaseURL). Is that the enhale backend?"
        } catch {
            errorMessage = "Couldn't reach the server at \(backendBaseURL). Is the backend running, and is the URL correct?"
        }
    }
}
