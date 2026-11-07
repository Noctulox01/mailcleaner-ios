import SwiftUI

/// Onglet « Nettoyer » : choix de la boîte puis liste des expéditeurs.
struct CleanView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = MailboxStore.shared
    @State private var selectedID: String?

    private var mailbox: Mailbox? {
        store.items.first { $0.id == selectedID } ?? store.items.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.loaded {
                    ProgressView()
                } else if let mailbox {
                    SendersView(mailbox: mailbox, showsPicker: store.items.count > 1, selectedID: $selectedID)
                        .id(mailbox.id)
                } else {
                    EmptyState(symbol: "sparkles", title: "Rien à nettoyer pour l'instant",
                               message: "Ajoutez une boîte mail depuis l'onglet Accueil, puis lancez une analyse.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
        .task(id: app.dataVersion) { if !store.loaded { await store.load() } }
    }
}

struct SendersView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tous", newsletters = "Newsletters", heavy = "Volumineux"
        var id: String { rawValue }
    }

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var jobs: JobCenter
    let mailbox: Mailbox
    var showsPicker = false
    var selectedID: Binding<String?>?

    @State private var scan: Scan?
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var selection = Set<String>()
    @State private var editing = false
    @State private var confirm: Action?
    @State private var unsubscribing: String?
    @State private var shown = 100

    enum Action: Identifiable {
        case delete([String]), block([String])
        var id: String {
            switch self {
            case .delete(let a): return "d" + a.joined()
            case .block(let a): return "b" + a.joined()
            }
        }
        var emails: [String] {
            switch self { case .delete(let a), .block(let a): return a }
        }
    }

    private var job: Job? { jobs.job(for: mailbox.id) }

    private var filtered: [Sender] {
        var list = scan?.senders ?? []
        switch filter {
        case .all: break
        case .newsletters: list = list.filter { $0.newsletter == true }
        case .heavy: list = list.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.email.contains(q) || ($0.name ?? "").lowercased().contains(q) }
        }
        return list
    }

    var body: some View {
        List(selection: $selection) {
            if showsPicker, let selectedID {
                Section {
                    Picker("Boîte mail", selection: Binding(get: { selectedID.wrappedValue ?? mailbox.id },
                                                            set: { selectedID.wrappedValue = $0 })) {
                        ForEach(MailboxStore.shared.items) { mb in Text(mb.email).tag(mb.id) }
                    }
                }
            }

            if let job, job.isRunning {
                Section { JobProgressRow(job: job) }
            }

            if loading && scan == nil {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if let error, scan == nil {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            } else if let scan {
                Section {
                    summary(scan)
                }
                Section {
                    Picker("Filtre", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    let list = filtered
                    if list.isEmpty {
                        Text(query.isEmpty ? "Aucun expéditeur dans cette catégorie." : "Aucun résultat pour « \(query) ».")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(list.prefix(shown)) { sender in
                        SenderRow(sender: sender, busy: unsubscribing == sender.email)
                            .tag(sender.email)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { confirm = .delete([sender.email]) } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                                Button { confirm = .block([sender.email]) } label: {
                                    Label("Bloquer", systemImage: "hand.raised")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                if sender.canUnsubscribe {
                                    Button { Task { await unsubscribe(sender) } } label: {
                                        Label("Désabonner", systemImage: "bell.slash")
                                    }
                                    .tint(.purple)
                                }
                                Button { Task { await protect(sender) } } label: {
                                    Label("Protéger", systemImage: "checkmark.shield")
                                }
                                .tint(.green)
                            }
                            .contextMenu { senderMenu(sender) }
                    }
                    if list.count > shown {
                        Button("Afficher plus (\(list.count - shown) restants)") { shown += 100 }
                    }
                } header: {
                    Text(Format.plural(filtered.count, "expéditeur"))
                } footer: {
                    Text("Balayez vers la gauche pour supprimer ou bloquer, vers la droite pour vous désabonner ou protéger.")
                }
            } else {
                Section {
                    EmptyState(symbol: "magnifyingglass", title: "Pas encore analysée",
                               message: "L'analyse lit les en-têtes de vos derniers messages pour regrouper les expéditeurs.",
                               actionTitle: "Analyser maintenant") { Task { await startScan() } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .searchable(text: $query, prompt: "Rechercher un expéditeur")
        .navigationTitle(mailbox.email)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { selectionBar }
        .refreshable { await load() }
        .task(id: app.dataVersion) { await load() }
        .onChange(of: editing) { on in if !on { selection.removeAll() } }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { action in
            switch action {
            case .delete(let emails):
                Button("Supprimer \(Format.plural(messageCount(emails), "message"))", role: .destructive) {
                    Task { await delete(emails, block: false) }
                }
            case .block(let emails):
                Button("Bloquer et supprimer", role: .destructive) { Task { await delete(emails, block: true) } }
            }
        } message: { action in
            switch action {
            case .delete:
                Text("Les messages vont dans la corbeille de votre boîte : vous pouvez encore les récupérer.")
            case .block:
                Text("Les messages actuels vont dans la corbeille, et les prochains seront supprimés quand vous appliquerez vos règles.")
            }
        }
    }

    // MARK: - Morceaux d'interface

    private func summary(_ scan: Scan) -> some View {
        HStack(spacing: 0) {
            summaryItem(Format.number(scan.senders.count), "expéditeurs")
            Divider().frame(height: 34)
            summaryItem(Format.number(scan.senders.filter { $0.newsletter == true }.count), "newsletters")
            Divider().frame(height: 34)
            summaryItem(Format.number(scan.scanned), "messages lus")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if scan != nil {
                Button(editing ? "OK" : "Sélectionner") { withAnimation { editing.toggle() } }
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                Task { await startScan() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(job?.isRunning == true)
            .accessibilityLabel("Relancer l'analyse")
        }
    }

    @ViewBuilder
    private var selectionBar: some View {
        if editing && !selection.isEmpty {
            HStack(spacing: 12) {
                Text(Format.plural(selection.count, "sélectionné"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { confirm = .block(Array(selection)) } label: {
                    Label("Bloquer", systemImage: "hand.raised.fill")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                Button(role: .destructive) { confirm = .delete(Array(selection)) } label: {
                    Label("Supprimer", systemImage: "trash.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
            .disabled(job?.isRunning == true)
            .transition(.move(edge: .bottom))
        }
    }

    @ViewBuilder
    private func senderMenu(_ sender: Sender) -> some View {
        Button { UIPasteboard.general.string = sender.email } label: { Label("Copier l'adresse", systemImage: "doc.on.doc") }
        if sender.canUnsubscribe {
            Button { Task { await unsubscribe(sender) } } label: { Label("Se désabonner", systemImage: "bell.slash") }
        }
        Button { Task { await protect(sender) } } label: { Label("Toujours garder", systemImage: "checkmark.shield") }
        Button { confirm = .block([sender.email]) } label: { Label("Bloquer", systemImage: "hand.raised") }
        Button(role: .destructive) { confirm = .delete([sender.email]) } label: { Label("Supprimer ses messages", systemImage: "trash") }
    }

    private var confirmTitle: String {
        guard let confirm else { return "" }
        let n = confirm.emails.count
        switch confirm {
        case .delete: return n == 1 ? "Supprimer les messages de \(confirm.emails[0]) ?" : "Supprimer les messages de \(n) expéditeurs ?"
        case .block: return n == 1 ? "Bloquer \(confirm.emails[0]) ?" : "Bloquer \(n) expéditeurs ?"
        }
    }

    private func messageCount(_ emails: [String]) -> Int {
        let set = Set(emails)
        return (scan?.senders ?? []).filter { set.contains($0.email) }.reduce(0) { $0 + $1.count }
    }

    // MARK: - Actions

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let env: ScanEnvelope = try await APIClient.shared.get("/api/mailboxes/\(mailbox.id)/senders")
            scan = env.scan
            error = nil
            let existing = Set((env.scan?.senders ?? []).map(\.email))
            selection = selection.intersection(existing)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startScan() async {
        do { try await jobs.start("/api/mailboxes/\(mailbox.id)/scan") } catch { app.show(error) }
    }

    private func delete(_ emails: [String], block: Bool) async {
        do {
            if block {
                let _: RulesEnvelope = try await APIClient.shared.post("/api/rules",
                                                                       ["list": "blocked", "action": "add", "values": emails])
            }
            try await jobs.start("/api/mailboxes/\(mailbox.id)/delete-senders", ["senders": emails])
            withAnimation { editing = false }
        } catch {
            app.show(error)
        }
    }

    private func protect(_ sender: Sender) async {
        do {
            let _: RulesEnvelope = try await APIClient.shared.post("/api/rules",
                                                                   ["list": "protected", "action": "add", "value": sender.email])
            app.show("\(sender.email) ne sera jamais supprimé.", style: .success)
        } catch {
            app.show(error)
        }
    }

    private func unsubscribe(_ sender: Sender) async {
        unsubscribing = sender.email
        defer { unsubscribing = nil }
        do {
            let r: UnsubscribeReply = try await APIClient.shared.post("/api/mailboxes/\(mailbox.id)/unsubscribe",
                                                                      ["email": sender.email])
            if r.done == true {
                app.show("Désabonnement effectué.", style: .success)
                await load()
            } else if let s = r.url, let url = URL(string: s) {
                if let w = r.warning { app.show(w) }
                await UIApplication.shared.open(url)
            }
        } catch {
            app.show(error)
        }
    }
}

struct SenderRow: View {
    let sender: Sender
    var busy = false

    var body: some View {
        HStack(spacing: 12) {
            Avatar(text: sender.displayName, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sender.displayName).font(.body.weight(.semibold)).lineLimit(1)
                    if sender.newsletter == true {
                        Text("Newsletter")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundStyle(.purple)
                    }
                    if sender.unsubscribed == true {
                        Image(systemName: "bell.slash.fill").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Désabonné")
                    }
                }
                Text(sender.email).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let subject = sender.subjects?.first, !subject.isEmpty {
                    Text(subject).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                if busy {
                    ProgressView()
                } else {
                    Text(Format.number(sender.count)).font(.headline.monospacedDigit())
                    Text(Format.bytes(sender.size)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint("\(sender.count) messages")
    }
}
