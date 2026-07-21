import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        if session.isAuthenticated {
            TabView {
                VoiceLogView()
                    .tabItem { Label("Log", systemImage: "mic.fill") }

                HistoryView()
                    .tabItem { Label("History", systemImage: "list.bullet") }

                HealthView()
                    .tabItem { Label("Health", systemImage: "heart.fill") }

                BloodWorkView()
                    .tabItem { Label("Labs", systemImage: "cross.case.fill") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
        } else {
            AuthView()
        }
    }
}
