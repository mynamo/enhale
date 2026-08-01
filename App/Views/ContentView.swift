import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        if session.isAuthenticated {
            TabView {
                VoiceLogView()
                    .tabItem { Label("Log", systemImage: "mic.fill") }

                HealthView()
                    .tabItem { Label("Health", systemImage: "heart.fill") }

                InsightsView()
                    .tabItem { Label("Insights", systemImage: "sparkles") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
        } else {
            AuthView()
        }
    }
}
