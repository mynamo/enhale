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
                    Button { Task { await sync() } } label: {
                        HStack {
                            Label("Sync Apple Health", systemImage: "heart.fill")
                            Spacer()
                            if isSyncing { ProgressView() }
                        }
                    }
                    .disabled(isSyncing)
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }

                if let summary {
                    workoutsSection(summary.workouts)
                    sleepSection(summary.sleep)
                    dailySection(summary.daily)
                }
            }
            .navigationTitle("Health")
            .task { await loadSummary() }
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

    private func sync() async {
        errorMessage = nil
        status = nil
        guard HealthKitService.isAvailable else {
            errorMessage = "Apple Health isn't available on this device."
            return
        }
        guard let client = session.makeClient() else {
            errorMessage = "Set a valid backend URL first."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await health.requestAuthorization()
            let request = try await health.buildSyncRequest(daysBack: 30)
            let result = try await client.syncHealth(request)
            status = "Synced \(result.workoutsUpserted) workouts, \(result.sleepUpserted) nights, \(result.dailyUpserted) days."
            await loadSummary()
        } catch EnhaleAPIClient.APIError.unauthorized {
            errorMessage = "Your session expired — please sign in again."
            session.logout()
        } catch {
            errorMessage = "Couldn't sync: \(error.localizedDescription)"
        }
    }

    private func loadSummary() async {
        guard let client = session.makeClient() else { return }
        summary = try? await client.healthSummary(days: 14)
    }

    // MARK: - Formatting

    private static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
