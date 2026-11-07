import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var app: AppState
    @State private var items: [ActivityItem] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error, items.isEmpty {
                    EmptyState(symbol: "wifi.exclamationmark", title: "Chargement impossible", message: error,
                               actionTitle: "Réessayer") { Task { await load() } }
                } else if items.isEmpty {
                    EmptyState(symbol: "clock", title: "Aucune activité",
                               message: "Vos analyses, suppressions et connexions apparaîtront ici.")
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { entry in
                        ActivityRow(item: entry.element)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Activité")
            .refreshable { await load() }
            .task(id: app.dataVersion) { await load() }
        }
    }

    private func load() async {
        do {
            let list: ActivityList = try await APIClient.shared.get("/api/activity")
            items = list.items
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

private struct ActivityRow: View {
    let item: ActivityItem

    private var style: (String, Color) {
        switch item.kind {
        case "success": return ("checkmark.circle.fill", .green)
        case "error": return ("exclamationmark.triangle.fill", .orange)
        default: return ("info.circle.fill", Brand.accent)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: style.0)
                .foregroundStyle(style.1)
                .font(.body)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text(Format.dateTime(item.ts)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
