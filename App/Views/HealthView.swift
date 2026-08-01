import SwiftUI
import EnhaleCore

/// The Health tab: pull workouts/sleep/activity from Apple Health and sync them
/// to the backend, then show a recent summary.
struct HealthView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var health = HealthKitService()

    @State private var summary: HealthSummary?
    @State private var meals: [ParsedMeal] = []
    @State private var isSyncing = false
    @State private var status: String?
    @State private var errorMessage: String?
    @State private var showPrimer = false
    @AppStorage("didShowHealthPrimer") private var didShowHealthPrimer = false
    @AppStorage("lastHealthSyncAt") private var lastHealthSyncAt: Double = 0
    @Environment(\.scenePhase) private var scenePhase

    /// Auto-sync at most this often (seconds) so opening the app / returning to
    /// this tab keeps data fresh without hammering HealthKit on every appear.
    private let autoSyncInterval: TimeInterval = 3600

    var body: some View {
        NavigationStack {
            List {
                if !HealthKitService.isAvailable {
                    Section {
                        Text("Apple Health isn't available here (it returns no data in the Simulator). Run on a real iPhone to sync workouts and sleep.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    statGrid(nutritionStats)
                } header: {
                    Text("Nutrition · today")
                }

                Section {
                    statGrid(workoutStats)
                } header: {
                    Text("Activity")
                }

                Section {
                    statGrid(sleepStats)
                } header: {
                    Text("Sleep")
                }

                Section {
                    Button { startSync() } label: {
                        HStack {
                            Label(isSyncing ? "Syncing…" : "Sync Apple Health", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing { ProgressView() }
                        }
                    }
                    .disabled(isSyncing)
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                    else if lastHealthSyncAt > 0 {
                        Text("Last synced \(relativeSync). Syncs automatically when you open the app.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }

                Section {
                    NavigationLink {
                        BloodWorkView()
                    } label: {
                        Label("Lab reports (blood work)", systemImage: "cross.case.fill")
                    }
                }

                if let summary {
                    workoutsSection(summary.workouts)
                    sleepSection(summary.sleep)
                    dailySection(summary.daily)
                }
            }
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EnhaleLogo() }
            }
            .task {
                await loadSummary()
                await loadMeals()
                await autoSyncIfDue()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await loadMeals(); await autoSyncIfDue() }
                }
            }
            .sheet(isPresented: $showPrimer) {
                HealthPermissionPrimer(
                    onContinue: {
                        didShowHealthPrimer = true
                        showPrimer = false
                        Task { await sync() }
                    },
                    onCancel: { showPrimer = false }
                )
            }
        }
    }

    // MARK: - Stat grid

    @ViewBuilder private func statGrid(_ items: [StatItem]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(items) { StatCard(icon: $0.icon, title: $0.title, value: $0.value, tint: $0.tint) }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    // MARK: - Sections

    @ViewBuilder private func workoutsSection(_ workouts: [WorkoutSample]) -> some View {
        Section("Recent workouts") {
            if workouts.isEmpty {
                Text("No workouts synced yet.").foregroundStyle(.secondary).font(.footnote)
            }
            ForEach(workouts.prefix(10)) { w in
                HStack {
                    VStack(alignment: .leading) {
                        Text(w.workoutType.capitalized).font(.subheadline)
                        Text(w.startAt, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(Self.duration(w.durationSeconds))
                        if let kcal = w.activeEnergyKcal {
                            Text("\(Int(kcal)) kcal").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func sleepSection(_ nights: [SleepNight]) -> some View {
        Section("Recent sleep") {
            if nights.isEmpty {
                Text("No sleep data synced yet.").foregroundStyle(.secondary).font(.footnote)
            }
            ForEach(nights.prefix(7)) { n in
                HStack {
                    Text(n.date)
                    Spacer()
                    Text(Self.duration(n.asleepSeconds) + " asleep").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder private func dailySection(_ daily: [DailyMetric]) -> some View {
        Section("Daily activity") {
            if daily.isEmpty {
                Text("No daily metrics synced yet.").foregroundStyle(.secondary).font(.footnote)
            }
            ForEach(daily.prefix(7)) { d in
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.date).font(.subheadline)
                    HStack(spacing: 12) {
                        if let s = d.steps { Text("\(s) steps") }
                        if let e = d.activeEnergyKcal { Text("\(Int(e)) kcal") }
                        if let hr = d.restingHeartRate { Text("\(Int(hr)) bpm rest") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    /// Show the plain-language primer before the first HealthKit prompt; after
    /// that, sync directly.
    private func startSync() {
        if didShowHealthPrimer {
            Task { await sync() }
        } else {
            showPrimer = true
        }
    }

    /// Sync automatically (no primer, no error banner) when the user has already
    /// opted in and it's been a while since the last sync.
    private func autoSyncIfDue() async {
        guard didShowHealthPrimer, HealthKitService.isAvailable, !isSyncing else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastHealthSyncAt > autoSyncInterval else { return }
        await sync(auto: true)
    }

    private func sync(auto: Bool = false) async {
        errorMessage = nil
        status = nil
        guard HealthKitService.isAvailable else {
            if !auto { errorMessage = "Apple Health isn't available on this device." }
            return
        }
        guard let client = session.makeClient() else {
            if !auto { errorMessage = "Set a valid backend URL first." }
            return
        }
        // Ask for notification permission on the first manual sync so we can post
        // the success/failure banner.
        if !auto { await NotificationManager.shared.requestAuthorization() }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await health.requestAuthorization()
            let request = try await health.buildSyncRequest(daysBack: 30)
            // 45s network timeout so a cold/slow backend fails fast instead of
            // spinning indefinitely.
            let result = try await client.syncHealth(request, timeout: 45)
            lastHealthSyncAt = Date().timeIntervalSince1970
            let message = "Synced \(result.workoutsUpserted) workouts, \(result.sleepUpserted) nights, \(result.dailyUpserted) days."
            if !auto {
                status = message
                await NotificationManager.shared.notify(title: "Health synced", body: message)
            }
            await loadSummary()
        } catch EnhaleAPIClient.APIError.unauthorized {
            errorMessage = "Your session expired — please sign in again."
            session.logout()
        } catch {
            // Auto-sync fails silently (e.g. offline); a manual sync reports it
            // both inline and as a notification.
            let reason = Self.friendlySyncError(error)
            if !auto {
                errorMessage = reason
                await NotificationManager.shared.notify(title: "Health sync failed", body: reason)
            }
        }
    }

    private static func friendlySyncError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Sync timed out — the server may be waking up. Try again in a moment."
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection — check your network and try again."
            default:
                break
            }
        }
        return "Couldn't sync: \(error.localizedDescription)"
    }

    private func loadSummary() async {
        guard let client = session.makeClient() else { return }
        summary = try? await client.healthSummary(days: 14)
    }

    private func loadMeals() async {
        guard let client = session.makeClient() else { return }
        if let fetched = try? await client.listMeals() { meals = fetched }
    }

    // MARK: - Summary stats

    /// A card in a summary grid.
    private struct StatItem: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let value: String
        let tint: Color
    }

    /// Nutrition today so far — total calories consumed and macronutrients from
    /// the meals logged today.
    private var nutritionStats: [StatItem] {
        let todayMeals = meals.filter { Calendar.current.isDateInToday($0.eatenAt) }
        let todayItems = todayMeals.flatMap(\.items)
        let calories = todayMeals.reduce(0.0) { $0 + $1.totalCalories }
        let protein = todayItems.compactMap(\.proteinGrams).reduce(0, +)
        let carbs = todayItems.compactMap(\.carbGrams).reduce(0, +)
        let fat = todayItems.compactMap(\.fatGrams).reduce(0, +)
        return [
            .init(icon: "fork.knife", title: "Calories", value: "\(Int(calories)) kcal", tint: .blue),
            .init(icon: "bolt.fill", title: "Protein", value: "\(Int(protein)) g", tint: .purple),
            .init(icon: "leaf.fill", title: "Carbs", value: "\(Int(carbs)) g", tint: .orange),
            .init(icon: "drop.fill", title: "Fat", value: "\(Int(fat)) g", tint: .yellow),
        ]
    }

    /// Activity — calories burned, steps, and resting heart rate from the most
    /// recent day that has data (today if available, otherwise the latest synced
    /// day), plus total workouts in the window. Placeholders when nothing synced.
    private var workoutStats: [StatItem] {
        let daily = (summary?.daily ?? []).sorted { $0.date > $1.date }
        let workouts = summary?.workouts ?? []

        let burned = daily.compactMap(\.activeEnergyKcal).first
            ?? workouts.compactMap(\.activeEnergyKcal).reduce(0, +)
        let steps = daily.compactMap(\.steps).first
        let hr = daily.compactMap(\.restingHeartRate).first

        return [
            .init(icon: "flame.fill", title: "Calories burned", value: "\(Int(burned)) kcal", tint: .pink),
            .init(icon: "shoeprints.fill", title: "Steps", value: steps.map { $0.formatted() } ?? "—", tint: .green),
            .init(icon: "heart.fill", title: "Resting HR", value: hr.map { "\(Int($0)) bpm" } ?? "—", tint: .red),
            .init(icon: "figure.run", title: "Workouts", value: "\(workouts.count)", tint: .orange),
        ]
    }

    /// Sleep — average hours over the window and a score for last night. Shows
    /// placeholders when no sleep data is synced.
    private var sleepStats: [StatItem] {
        let nights = summary?.sleep ?? []
        let avgValue = nights.isEmpty
            ? "—"
            : Self.duration(nights.map(\.asleepSeconds).reduce(0, +) / Double(nights.count))
        let scoreValue = nights.max(by: { $0.date < $1.date }).map { "\(Self.sleepScore($0))" } ?? "—"
        return [
            .init(icon: "bed.double.fill", title: "Avg hours", value: avgValue, tint: .indigo),
            .init(icon: "moon.stars.fill", title: "Sleep score", value: scoreValue, tint: .mint),
        ]
    }

    /// A 0–100 heuristic sleep score for one night: duration vs an 8h target,
    /// efficiency (asleep / in-bed), and restorative share (deep + REM). Apple
    /// Health has no native score, so this is our own composite.
    private static func sleepScore(_ n: SleepNight) -> Int {
        let hours = n.asleepSeconds / 3600
        let duration = min(hours / 8, 1)

        var efficiency = 1.0
        if let inBed = n.inBedSeconds, inBed > 0 {
            efficiency = min(n.asleepSeconds / inBed, 1)
        }

        let restorative = (n.deepSeconds ?? 0) + (n.remSeconds ?? 0)
        let hasStages = n.deepSeconds != nil || n.remSeconds != nil
        let score: Double
        if hasStages, n.asleepSeconds > 0 {
            // 60% duration, 20% efficiency, 20% restorative (target ~40% of sleep).
            let restShare = min((restorative / n.asleepSeconds) / 0.4, 1)
            score = duration * 60 + efficiency * 20 + restShare * 20
        } else {
            // No stage data — weight duration and efficiency to fill 100.
            score = duration * 75 + efficiency * 25
        }
        return Int(score.rounded())
    }

    // MARK: - Formatting

    private var relativeSync: String {
        guard lastHealthSyncAt > 0 else { return "never" }
        let date = Date(timeIntervalSince1970: lastHealthSyncAt)
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// One metric tile in the Health summary grid.
private struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3).bold()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
