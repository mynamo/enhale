import SwiftUI
import EnhaleCore

/// "Ask enhale" — the flagship. Ask about a concern; get ranked root-cause
/// hypotheses grounded in your data, plus exactly what data is missing.
struct AskView: View {
    @EnvironmentObject private var session: SessionManager

    @State private var concern = ""
    @State private var report: InvestigationReport?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ask about anything you want to understand — enhale correlates your meals, activity, sleep, and labs, and tells you what's missing to get to the root cause.")
                    .font(.footnote).foregroundStyle(.secondary)

                TextField("e.g. Why do I have grey hair?", text: $concern, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    focused = false
                    Task { await ask() }
                } label: {
                    HStack {
                        if isBusy { ProgressView().tint(.white) }
                        Text(isBusy ? "Investigating…" : "Ask enhale")
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || concern.trimmingCharacters(in: .whitespaces).isEmpty)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                if let report { reportView(report) }
            }
            .padding()
        }
        .navigationTitle("Ask enhale")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { if report == nil { report = try? await session.makeClient()?.listInvestigations().first } } }
    }

    @ViewBuilder private func reportView(_ r: InvestigationReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            Text("“\(r.concern)”").font(.headline)
            Text(r.summary).font(.subheadline)

            if !r.hypotheses.isEmpty {
                Text("Possible contributors").font(.headline)
                ForEach(r.hypotheses) { h in HypothesisCard(h: h) }
            }

            if !r.dataGaps.isEmpty {
                Text("What would help to know").font(.headline)
                ForEach(r.dataGaps) { gap in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(gap.item, systemImage: "questionmark.circle").font(.subheadline).fontWeight(.semibold)
                        Text(gap.why).font(.caption).foregroundStyle(.secondary)
                        Text("→ \(gap.howToGet)").font(.caption).foregroundStyle(.blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if !r.nextSteps.isEmpty {
                Text("Next steps").font(.headline)
                ForEach(r.nextSteps, id: \.self) { step in
                    Label(step, systemImage: "checkmark.circle").font(.subheadline)
                }
            }

            Text(r.disclaimer).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private func ask() async {
        guard let client = session.makeClient() else { errorMessage = "Set a backend URL first."; return }
        isBusy = true; defer { isBusy = false }
        errorMessage = nil
        do {
            report = try await client.investigate(concern: concern)
        } catch EnhaleAPIClient.APIError.unauthorized {
            session.logout()
        } catch {
            errorMessage = "Couldn't investigate: \(error.localizedDescription)"
        }
    }
}

private struct HypothesisCard: View {
    let h: Hypothesis

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(h.title).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(h.likelihood.uppercased())
                    .font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
            }
            Text(h.rationale).font(.subheadline)
            ForEach(h.supporting, id: \.self) { s in
                Label(s, systemImage: "checkmark").font(.caption).foregroundStyle(.green)
            }
            ForEach(h.missing, id: \.self) { m in
                Label(m, systemImage: "questionmark").font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var color: Color {
        switch h.likelihood {
        case "high": return .red
        case "medium": return .orange
        default: return .green
        }
    }
}
