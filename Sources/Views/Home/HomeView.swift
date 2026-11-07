import SwiftUI

/// Charge et partage la liste des boîtes mail entre les onglets.
@MainActor
final class MailboxStore: ObservableObject {
    static let shared = MailboxStore()
    @Published var items: [Mailbox] = []
    @Published var loaded = false
    @Published var error: String?

    func load() async {
        do {
            let list: MailboxList = try await APIClient.shared.get("/api/mailboxes")
            items = list.items
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var jobs: JobCenter
    @ObservedObject private var store = MailboxStore.shared
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greeting
                    stats
                    mailboxSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MailCleaner")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .accessibilityLabel("Ajouter une boîte mail")
                }
            }
            .refreshable {
                await store.load()
                await app.refreshMe()
            }
            .sheet(isPresented: $showAdd) { AddMailboxView() }
            .navigationDestination(for: Mailbox.self) { MailboxDetailView(mailbox: $0) }
        }
        .task(id: app.dataVersion) { await store.load() }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.user?.firstName.isEmpty == false ? "Bonjour \(app.user!.firstName)" : "Bonjour")
                .font(.title2.weight(.bold))
            Text(store.items.isEmpty ? "Connectez une boîte mail pour commencer." : "Voici où en sont vos boîtes mail.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(value: Format.number(app.user?.deletedCount), label: "messages supprimés", symbol: "trash.fill", tint: .red)
            StatTile(value: Format.number(app.user?.scannedCount), label: "messages analysés", symbol: "magnifyingglass", tint: Brand.accent)
            StatTile(value: Format.number(store.items.count), label: store.items.count > 1 ? "boîtes connectées" : "boîte connectée",
                     symbol: "tray.2.fill", tint: .purple)
            StatTile(value: Format.number(app.user?.unsubscribedCount), label: "désabonnements", symbol: "hand.wave.fill", tint: .orange)
        }
    }

    @ViewBuilder
    private var mailboxSection: some View {
        Text("Boîtes mail").font(.headline).padding(.top, 4)
        if !store.loaded {
            ProgressView().frame(maxWidth: .infinity).padding(30)
        } else if let error = store.error, store.items.isEmpty {
            EmptyState(symbol: "wifi.exclamationmark", title: "Chargement impossible", message: error,
                       actionTitle: "Réessayer") { Task { await store.load() } }
        } else if store.items.isEmpty {
            EmptyState(symbol: "tray", title: "Aucune boîte mail",
                       message: "Ajoutez votre boîte iCloud, Gmail ou Outlook avec un mot de passe d'application.",
                       actionTitle: "Ajouter une boîte mail") { showAdd = true }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            VStack(spacing: 10) {
                ForEach(store.items) { mb in
                    NavigationLink(value: mb) {
                        MailboxCard(mailbox: mb, job: jobs.job(for: mb.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct MailboxCard: View {
    let mailbox: Mailbox
    let job: Job?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ProviderBadge(provider: mailbox.providerInfo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mailbox.email).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            if let job, job.isRunning { JobProgressRow(job: job) }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard let s = mailbox.lastScan, let ts = s.ts else { return "\(mailbox.providerInfo.label) · jamais analysée" }
        return "\(mailbox.providerInfo.label) · analysée \(Format.relative(ts)) · \(Format.plural(s.senders ?? 0, "expéditeur"))"
    }
}

/// Détail d'une boîte : dossiers, analyse, nettoyage, déconnexion.
struct MailboxDetailView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var jobs: JobCenter
    @Environment(\.dismiss) private var dismiss
    let mailbox: Mailbox

    @State private var overview: Overview?
    @State private var overviewError: String?
    @State private var loadingOverview = false
    @State private var confirmEmpty: String?
    @State private var confirmRemove = false

    private var job: Job? { jobs.job(for: mailbox.id) }
    private var current: Mailbox { MailboxStore.shared.items.first { $0.id == mailbox.id } ?? mailbox }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ProviderBadge(provider: mailbox.providerInfo, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mailbox.email).font(.headline).lineLimit(1).truncationMode(.middle)
                        Text("\(mailbox.providerInfo.label) · connectée \(Format.relative(mailbox.createdAt))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if let job, job.isRunning { JobProgressRow(job: job) }
            }

            Section("Dossiers") {
                if loadingOverview && overview == nil {
                    HStack { ProgressView(); Text("Lecture des dossiers…").foregroundStyle(.secondary) }
                } else if let overviewError {
                    Label(overviewError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote)
                } else if let overview {
                    folderRow("Boîte de réception", count: overview.inbox, symbol: "tray.fill", tint: Brand.accent)
                    if overview.trash != nil {
                        folderRow(overview.trashName ?? "Corbeille", count: overview.trash, symbol: "trash.fill", tint: .gray,
                                  action: ("Vider", "trash"))
                    }
                    if overview.junk != nil {
                        folderRow(overview.junkName ?? "Indésirables", count: overview.junk, symbol: "xmark.bin.fill", tint: .orange,
                                  action: ("Vider", "junk"))
                    }
                }
            }

            Section {
                Button {
                    Task { await start("/api/mailboxes/\(mailbox.id)/scan") }
                } label: {
                    Label(current.lastScan == nil ? "Analyser la boîte" : "Relancer l'analyse", systemImage: "magnifyingglass")
                }
                .disabled(job?.isRunning == true)
                NavigationLink {
                    SendersView(mailbox: mailbox)
                } label: {
                    Label("Voir les expéditeurs", systemImage: "person.2.fill")
                }
                .disabled(current.lastScan == nil)
                Button {
                    Task { await start("/api/mailboxes/\(mailbox.id)/apply-rules") }
                } label: {
                    Label("Appliquer mes règles", systemImage: "wand.and.stars")
                }
                .disabled(job?.isRunning == true)
            } header: {
                Text("Nettoyage")
            } footer: {
                if let s = current.lastScan, let ts = s.ts {
                    Text("Dernière analyse \(Format.relative(ts)) : \(Format.plural(s.scanned ?? 0, "message")) lus, \(Format.plural(s.senders ?? 0, "expéditeur")), \(Format.plural(s.newsletters ?? 0, "newsletter")).")
                } else {
                    Text("L'analyse lit uniquement les en-têtes (expéditeur, objet, date) : jamais le contenu de vos messages.")
                }
            }

            Section {
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("Déconnecter cette boîte", systemImage: "minus.circle")
                }
            } footer: {
                Text("Vos e-mails ne sont pas touchés : MailCleaner oublie simplement l'accès.")
            }
        }
        .navigationTitle(mailbox.providerInfo.label)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadOverview() }
        .task(id: app.dataVersion) { await loadOverview() }
        .confirmationDialog("Vider ce dossier ?", isPresented: Binding(get: { confirmEmpty != nil }, set: { if !$0 { confirmEmpty = nil } }),
                            titleVisibility: .visible) {
            Button("Vider définitivement", role: .destructive) {
                if let kind = confirmEmpty {
                    Task { await start("/api/mailboxes/\(mailbox.id)/empty", ["folder": kind]) }
                }
            }
        } message: {
            Text("Les messages seront supprimés définitivement. Cette action est irréversible.")
        }
        .confirmationDialog("Déconnecter \(mailbox.email) ?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Déconnecter", role: .destructive) { Task { await remove() } }
        } message: {
            Text("L'analyse et le lien avec cette boîte seront effacés. Vos e-mails restent intacts.")
        }
    }

    private func folderRow(_ name: String, count: Int?, symbol: String, tint: Color, action: (String, String)? = nil) -> some View {
        HStack {
            Label { Text(name) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            Spacer()
            Text(count.map { Format.number($0) } ?? "—").monospacedDigit().foregroundStyle(.secondary)
            if let action, (count ?? 0) > 0 {
                Button(action.0) { confirmEmpty = action.1 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(job?.isRunning == true)
            }
        }
    }

    private func loadOverview() async {
        loadingOverview = true
        defer { loadingOverview = false }
        do {
            overview = try await APIClient.shared.get("/api/mailboxes/\(mailbox.id)/overview")
            overviewError = nil
        } catch {
            overviewError = error.localizedDescription
        }
    }

    private func start(_ path: String, _ body: [String: Any] = [:]) async {
        do { try await jobs.start(path, body) } catch { app.show(error) }
    }

    private func remove() async {
        do {
            let _: Empty = try await APIClient.shared.post("/api/mailboxes/\(mailbox.id)/remove")
            app.show("Boîte déconnectée.", style: .success)
            app.dataChanged()
            dismiss()
        } catch {
            app.show(error)
        }
    }
}
