import SwiftUI
import UniformTypeIdentifiers
import EnhaleCore

/// The Labs tab: upload a blood-work report (PDF/PNG/JPEG); the backend extracts
/// the markers via Claude. Lists past panels; tap one for the full results.
struct BloodWorkView: View {
    @EnvironmentObject private var session: SessionManager

    @State private var panels: [BloodWorkPanel] = []
    @State private var isImporting = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
                if panels.isEmpty && !isUploading {
                    ContentUnavailableView {
                        Label("No lab reports yet", systemImage: "cross.case")
                    } description: {
                        Text("Upload a blood work report (PDF, PNG, or JPEG) and enhale will pull out the results.")
                    } actions: {
                        uploadButton
                    }
                } else {
                    List {
                        if isUploading {
                            HStack { ProgressView(); Text("Reading report…").foregroundStyle(.secondary) }
                        }
                        ForEach(panels) { panel in
                            NavigationLink { BloodWorkDetailView(panel: panel) } label: { PanelRow(panel: panel) }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Labs")
            .toolbar { ToolbarItem(placement: .primaryAction) { uploadButton } }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf, .png, .jpeg],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await upload(url) }
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red).padding()
                }
            }
        .onAppear { Task { await load() } }
    }

    private var uploadButton: some View {
        Button { errorMessage = nil; isImporting = true } label: {
            Label("Upload report", systemImage: "square.and.arrow.up")
        }
        .disabled(isUploading)
    }

    // MARK: - Actions

    private func load() async {
        guard let client = session.makeClient() else { return }
        do { panels = try await client.listBloodWork() }
        catch EnhaleAPIClient.APIError.unauthorized { session.logout() }
        catch { errorMessage = "Couldn't load reports: \(error.localizedDescription)" }
    }

    private func upload(_ url: URL) async {
        guard let client = session.makeClient() else {
            errorMessage = "Set a valid backend URL first."; return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Couldn't read that file."; return
        }
        isUploading = true
        defer { isUploading = false }
        errorMessage = nil
        do {
            _ = try await client.uploadBloodWork(
                fileData: data, filename: url.lastPathComponent, mimeType: Self.mime(for: url)
            )
            await load()
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
        }
    }

    private func delete(_ offsets: IndexSet) {
        guard let client = session.makeClient() else { return }
        let ids = offsets.map { panels[$0].id }
        panels.remove(atOffsets: offsets)
        Task { for id in ids { try? await client.deleteBloodWork(id: id) } }
    }

    private static func mime(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }
}

private struct PanelRow: View {
    let panel: BloodWorkPanel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(panel.collectedOn ?? panel.createdAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Report")
                .font(.headline)
            HStack {
                Text("\(panel.markers.count) results").font(.caption).foregroundStyle(.secondary)
                if panel.outOfRangeCount > 0 {
                    Text("\(panel.outOfRangeCount) flagged")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Text(panel.sourceFilename).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Full marker list for one panel, out-of-range values highlighted.
struct BloodWorkDetailView: View {
    let panel: BloodWorkPanel

    var body: some View {
        List {
            if let note = panel.note {
                Section { Text(note).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(panel.markers) { marker in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(marker.name)
                            if let range = marker.referenceRange {
                                Text("ref \(range)").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text([marker.value, marker.unit].compactMap { $0 }.joined(separator: " "))
                                .foregroundStyle(Self.color(for: marker.flag))
                            if let flag = marker.flag, marker.isOutOfRange {
                                Text(flag.uppercased()).font(.caption2).foregroundStyle(Self.color(for: flag))
                            }
                        }
                    }
                }
            } header: {
                Text(panel.collectedOn.map { "Collected \($0)" } ?? "Results")
            }
        }
        .navigationTitle("Lab results")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func color(for flag: String?) -> Color {
        switch flag {
        case "high": return .red
        case "low": return .orange
        default: return .primary
        }
    }
}
