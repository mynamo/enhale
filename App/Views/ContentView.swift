import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        if session.isAuthenticated {
            TabView {
                VoiceLogView()
                    .tabItem { Label("Log", systemImage: "mic.fill") }

                TodayView()
                    .tabItem { Label("Today", systemImage: "list.bullet") }

                HealthView()
                    .tabItem { Label("Health", systemImage: "heart.fill") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
        } else {
            AuthView()
        }
    }
}
