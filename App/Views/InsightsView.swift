import SwiftUI
import EnhaleCore

/// The payoff: a recommendations report synthesized from meals + health + labs.
struct InsightsView: View {
    @EnvironmentObject private var session: SessionManager

    @State private var report: InsightReport?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isGenerating {
                        HStack { ProgressView(); Text("Analyzing your meals, activity, and labs…").foregroundStyle(.secondary) }
                            .padding(.top)
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }

                    if let report {
                        reportView(report)
                    } else if !isGenerating {
                        ContentUnavailableView {
                            Label("No insights yet", systemImage: "sparkles")
                        } description: {
                            Text("Once you've logged some meals and synced Apple Health, generate personalized recommendations.")
                        }
                        .padding(.top, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await generate() } } label: {
                        Label("Generate", systemImage: "sparkles")
                    }
                    .disabled(isGenerating)
                }
            }
            .onAppear { Task { await loadLatest() } }
        }
    }

    @ViewBuilder private func reportView(_ report: InsightReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let at = report.generatedAt {
                Text("Generated \(at.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text(report.summary).font(.body)

            if !report.observations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What I noticed").font(.headline)
                    ForEach(report.observations, id: \.self) { o in
                        Label(o, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                            .font(.subheadline)
                    }
                }
            }

            if !report.recommendations.isEmpty {
                Text("Recommendations").font(.headline)
                ForEach(report.recommendations) { rec in
                    RecommendationCard(rec: rec)
                }
            }

            Text(report.disclaimer)
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func loadLatest() async {
        guard let client = session.makeClient() else { return }
        report = (try? await client.listInsights())?.first
    }

    private func generate() async {
        guard let client = session.makeClient() else {
            errorMessage = "Set a valid backend URL first."; return
        }
        isGenerating = true
        defer { isGenerating = false }
        errorMessage = nil
        do {
            report = try await client.generateInsights()
        } catch EnhaleAPIClient.APIError.unauthorized {
            session.logout()
        } catch {
            errorMessage = "Couldn't generate insights: \(error.localizedDescription)"
        }
    }
}

private struct RecommendationCard: View {
    let rec: Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rec.title).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(rec.priority.uppercased())
                    .font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(priorityColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(priorityColor)
            }
            Text(rec.detail).font(.subheadline)
            Text(rec.rationale).font(.caption).foregroundStyle(.secondary).italic()
            Text(rec.category.capitalized).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var priorityColor: Color {
        switch rec.priority {
        case "high": return .red
        case "medium": return .orange
        default: return .green
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}
