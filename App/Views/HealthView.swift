import SwiftUI
import EnhaleCore

/// The Health tab: pull workouts/sleep/activity from Apple Health and sync them
/// to the backend, then show a recent summary.
struct HealthView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var health = HealthKitService()

    @State private var summary: HealthSummary?
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

                if let summary, !summaryStats(summary).isEmpty {
                    Section {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(summaryStats(summary)) {
                                StatCard(icon: $0.icon, title: $0.title, value: $0.value, tint: $0.tint)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
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
            .task {
                await loadSummary()
                await autoSyncIfDue()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await autoSyncIfDue() } }
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
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await health.requestAuthorization()
            let request = try await health.buildSyncRequest(daysBack: 30)
            let result = try await client.syncHealth(request)
            lastHealthSyncAt = Date().timeIntervalSince1970
            if !auto {
                status = "Synced \(result.workoutsUpserted) workouts, \(result.sleepUpserted) nights, \(result.dailyUpserted) days."
            }
            await loadSummary()
        } catch EnhaleAPIClient.APIError.unauthorized {
            errorMessage = "Your session expired — please sign in again."
            session.logout()
        } catch {
            // Auto-sync fails silently (e.g. offline) — the manual button and the
            // last-synced timestamp still tell the user what's going on.
            if !auto { errorMessage = "Couldn't sync: \(error.localizedDescription)" }
        }
    }

    private func loadSummary() async {
        guard let client = session.makeClient() else { return }
        summary = try? await client.healthSummary(days: 14)
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
        return items
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
