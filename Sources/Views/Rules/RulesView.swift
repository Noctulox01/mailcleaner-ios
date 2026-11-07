import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var jobs: JobCenter
    @ObservedObject private var store = MailboxStore.shared
    @State private var rules: Rules?
    @State private var error: String?
    @State private var adding: RuleList?
    @State private var newValue = ""
    @State private var showContacts = false

    var body: some View {
        NavigationStack {
            List {
                if let rules {
                    Section {
                        Toggle(isOn: Binding(get: { rules.contactsAuto ?? true }, set: { v in Task { await setContacts(v) } })) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Protéger mes contacts")
                                    Text("Les personnes à qui vous avez écrit ne sont jamais supprimées.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(.green)
                            }
                        }
                        if rules.contactsAuto ?? true {
                            Button {
                                showContacts = true
                            } label: {
                                HStack {
                                    Text("\(Format.plural(rules.contacts?.count ?? 0, "contact")) protégés")
                                    Spacer()
                                    if let ts = rules.contactsSyncedAt {
                                        Text("synchronisés \(Format.relative(ts))").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled((rules.contacts ?? []).isEmpty)
                            ForEach(store.items) { mb in
                                Button {
                                    Task { await start("/api/mailboxes/\(mb.id)/sync-contacts") }
                                } label: {
                                    Label("Synchroniser depuis \(mb.email)", systemImage: "arrow.triangle.2.circlepath")
                                        .lineLimit(1)
                                }
                                .disabled(jobs.job(for: mb.id)?.isRunning == true)
                            }
                        }
                    } header: {
                        Text("Liste blanche automatique")
                    }

                    ForEach(RuleList.allCases) { kind in
                        ruleSection(kind, values: values(rules, kind))
                    }

                    if !store.items.isEmpty {
                        Section {
                            ForEach(store.items) { mb in
                                if let job = jobs.job(for: mb.id), job.isRunning {
                                    JobProgressRow(job: job)
                                } else {
                                    Button {
                                        Task { await start("/api/mailboxes/\(mb.id)/apply-rules") }
                                    } label: {
                                        Label("Appliquer à \(mb.email)", systemImage: "wand.and.stars").lineLimit(1)
                                    }
                                }
                            }
                        } header: {
                            Text("Appliquer maintenant")
                        } footer: {
                            Text("Supprime les messages des expéditeurs bloqués et ceux dont l'objet contient un mot-clé. Les expéditeurs protégés et vos contacts sont toujours épargnés.")
                        }
                    }
                } else if let error {
                    EmptyState(symbol: "wifi.exclamationmark", title: "Chargement impossible", message: error,
                               actionTitle: "Réessayer") { Task { await load() } }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Règles")
            .refreshable { await load() }
            .task { await load() }
            .alert(adding?.title ?? "", isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
                TextField(adding?.placeholder ?? "", text: $newValue)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Annuler", role: .cancel) { newValue = "" }
                Button("Ajouter") {
                    if let kind = adding { Task { await update(kind, "add", newValue) } }
                    newValue = ""
                }
            } message: {
                Text(adding?.help ?? "")
            }
            .sheet(isPresented: $showContacts) { ContactsSheet(contacts: rules?.contacts ?? []) }
        }
    }

    private func values(_ r: Rules, _ kind: RuleList) -> [String] {
        switch kind {
        case .blocked: return r.blocked
        case .keywords: return r.keywords
        case .protected: return r.protected
        }
    }

    private func ruleSection(_ kind: RuleList, values: [String]) -> some View {
        Section {
            ForEach(values, id: \.self) { v in
                Text(v).lineLimit(1)
            }
            .onDelete { idx in
                let removed = idx.map { values[$0] }
                Task { for v in removed { await update(kind, "remove", v) } }
            }
            Button {
                adding = kind
            } label: {
                Label("Ajouter", systemImage: "plus.circle.fill")
            }
        } header: {
            Label(kind.title, systemImage: kind.symbol)
        } footer: {
            Text(kind.help)
        }
    }

    private func load() async {
        do {
            let env: RulesEnvelope = try await APIClient.shared.get("/api/rules")
            rules = env.rules
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        if !store.loaded { await store.load() }
    }

    private func update(_ kind: RuleList, _ action: String, _ value: String) async {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        do {
            let env: RulesEnvelope = try await APIClient.shared.post("/api/rules", ["list": kind.rawValue, "action": action, "value": v])
            withAnimation { rules = env.rules }
        } catch {
            app.show(error)
        }
    }

    private func setContacts(_ enabled: Bool) async {
        do {
            let env: RulesEnvelope = try await APIClient.shared.post("/api/rules/contacts", ["enabled": enabled])
            withAnimation { rules = env.rules }
        } catch {
            app.show(error)
        }
    }

    private func start(_ path: String) async {
        do { try await jobs.start(path) } catch { app.show(error) }
    }
}

private struct ContactsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contacts: [String]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(contacts.filter { query.isEmpty || $0.contains(query.lowercased()) }, id: \.self) { c in
                Text(c).lineLimit(1)
            }
            .searchable(text: $query, prompt: "Rechercher")
            .navigationTitle("Contacts protégés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}
