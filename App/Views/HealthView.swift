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

                if !todayStats.isEmpty {
                    Section {
                        statGrid(todayStats)
                    } header: {
                        Text("Today")
                    }
                }

                if let summary, !summaryStats(summary).isEmpty {
                    Section {
                        statGrid(summaryStats(summary))
                    } header: {
                        Text("Last 14 days")
                    }
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
        Section("Workouts") {
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
        Section("Sleep") {
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

    /// A card in the "Last 14 days" grid.
    private struct StatItem: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let value: String
        let tint: Color
    }

    /// Aggregate the synced summary into a few glanceable numbers. Only metrics
    /// that actually have data produce a card.
    private func summaryStats(_ s: HealthSummary) -> [StatItem] {
        var items: [StatItem] = []

        if !s.sleep.isEmpty {
            let avg = s.sleep.map(\.asleepSeconds).reduce(0, +) / Double(s.sleep.count)
            items.append(.init(icon: "bed.double.fill", title: "Avg sleep", value: Self.duration(avg), tint: .indigo))
        }
        if !s.workouts.isEmpty {
            items.append(.init(icon: "figure.run", title: "Workouts", value: "\(s.workouts.count)", tint: .orange))
        }
        let steps = s.daily.compactMap(\.steps)
        if !steps.isEmpty {
            items.append(.init(icon: "shoeprints.fill", title: "Avg steps", value: (steps.reduce(0, +) / steps.count).formatted(), tint: .green))
        }
        let rhr = s.daily.compactMap(\.restingHeartRate)
        if !rhr.isEmpty {
            let avg = rhr.reduce(0, +) / Double(rhr.count)
            items.append(.init(icon: "heart.fill", title: "Resting HR", value: "\(Int(avg)) bpm", tint: .red))
        }
        let energy = s.daily.compactMap(\.activeEnergyKcal)
        if !energy.isEmpty {
            let avg = energy.reduce(0, +) / Double(energy.count)
            items.append(.init(icon: "flame.fill", title: "Avg active", value: "\(Int(avg)) kcal", tint: .pink))
        }
        if let weight = s.daily.sorted(by: { $0.date > $1.date }).compactMap(\.bodyMassKg).first {
            items.append(.init(icon: "scalemass.fill", title: "Weight", value: String(format: "%.1f kg", weight), tint: .teal))
        }
        // Average daily calorie intake, computed from logged meals over the window.
        let byDay = Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.eatenAt) }
        if !byDay.isEmpty {
            let perDay = byDay.values.map { day in day.reduce(0.0) { $0 + $1.totalCalories } }
            let avg = perDay.reduce(0, +) / Double(perDay.count)
            items.append(.init(icon: "fork.knife", title: "Avg cal/day", value: "\(Int(avg)) kcal", tint: .blue))
        }
        return items
    }

    /// "Today so far": intake + macros from today's logged meals, plus calories
    /// burned and last night's sleep from Apple Health.
    private var todayStats: [StatItem] {
        var items: [StatItem] = []
        let todayMeals = meals.filter { Calendar.current.isDateInToday($0.eatenAt) }
        let todayItems = todayMeals.flatMap(\.items)

        let calories = todayMeals.reduce(0.0) { $0 + $1.totalCalories }
        items.append(.init(icon: "fork.knife", title: "Calories in", value: "\(Int(calories)) kcal", tint: .blue))

        let protein = todayItems.compactMap(\.proteinGrams).reduce(0, +)
        let carbs = todayItems.compactMap(\.carbGrams).reduce(0, +)
        let fat = todayItems.compactMap(\.fatGrams).reduce(0, +)
        if protein + carbs + fat > 0 {
            items.append(.init(icon: "bolt.fill", title: "Protein", value: "\(Int(protein)) g", tint: .purple))
            items.append(.init(icon: "leaf.fill", title: "Carbs", value: "\(Int(carbs)) g", tint: .orange))
            items.append(.init(icon: "drop.fill", title: "Fat", value: "\(Int(fat)) g", tint: .yellow))
        }

        if let summary {
            let todayDaily = summary.daily.first { $0.date == Self.todayKey }
            let workoutBurn = summary.workouts
                .filter { Calendar.current.isDateInToday($0.startAt) }
                .compactMap(\.activeEnergyKcal).reduce(0, +)
            let burned = todayDaily?.activeEnergyKcal ?? workoutBurn
            if burned > 0 {
                items.append(.init(icon: "flame.fill", title: "Burned", value: "\(Int(burned)) kcal", tint: .pink))
            }
            if let lastNight = summary.sleep.max(by: { $0.date < $1.date }) {
                items.append(.init(icon: "bed.double.fill", title: "Sleep", value: Self.duration(lastNight.asleepSeconds), tint: .indigo))
            }
        }
        return items
    }

    /// Today's local calendar day as a `yyyy-MM-dd` key, matching the format the
    /// device uses for `DailyMetric.date`.
    private static var todayKey: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
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
