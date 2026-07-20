import SwiftUI

@main
struct EnhaleApp: App {
    @StateObject private var store = MealStore()
    @StateObject private var session = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(session)
        }
    }
}
