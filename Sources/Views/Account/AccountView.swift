import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var app: AppState
    @State private var mfa: MFAStatus?
    @State private var billing: BillingInfo?
    @State private var confirmLogout = false
    @State private var askDelete = false
    @State private var exportURL: URL?
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            List {
                if let user = app.user {
                    Section {
                        HStack(spacing: 14) {
                            Avatar(text: user.displayName, size: 58)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayName).font(.title3.weight(.semibold)).lineLimit(1)
                                Text(user.email).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                if user.isOwner {
                                    Text("Propriétaire du serveur").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    if user.mustChangePassword == true {
                        Section {
                            Label("Votre mot de passe a été réinitialisé par l'administrateur : choisissez-en un nouveau.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                    }

                    Section("Profil et sécurité") {
                        NavigationLink { ProfileNameView() } label: {
                            row("Prénom", value: user.firstName.isEmpty ? "Non renseigné" : user.firstName, symbol: "person.fill", tint: .blue)
                        }
                        NavigationLink { ChangePasswordView() } label: {
                            row("Mot de passe", value: nil, symbol: "key.fill", tint: .gray)
                        }
                        NavigationLink { MFASettingsView(status: $mfa) } label: {
                            row("Double authentification", value: mfaSummary, symbol: "lock.shield.fill",
                                tint: (mfa?.enabled ?? user.mfa ?? false) ? .green : .orange)
                        }
                    }

                    Section("Abonnement") {
                        NavigationLink { SubscriptionView(info: $billing) } label: {
                            row("Offre", value: user.billing?.planLabel ?? "Gratuit", symbol: "star.fill", tint: .yellow)
                        }
                    }

                    Section {
                        Button {
                            Task { await export() }
                        } label: {
                            HStack {
                                row("Exporter mes données", value: nil, symbol: "square.and.arrow.down.fill", tint: .teal)
                                Spacer()
                                if exporting { ProgressView() }
                            }
                        }
                        .foregroundStyle(.primary)
                        Link(destination: APIClient.shared.url("/confidentialite.html") ?? ServerSettings.url) {
                            row("Confidentialité", value: nil, symbol: "hand.raised.fill", tint: .indigo)
                        }
                        .foregroundStyle(.primary)
                        Link(destination: APIClient.shared.url("/faq.html") ?? ServerSettings.url) {
                            row("Aide et FAQ", value: nil, symbol: "questionmark.circle.fill", tint: .purple)
                        }
                        .foregroundStyle(.primary)
                    } header: {
                        Text("Mes données")
                    } footer: {
                        Text("MailCleaner ne lit jamais le contenu de vos messages et ne revend aucune donnée.")
                    }

                    Section {
                        Button("Se déconnecter") { confirmLogout = true }
                        if !user.isOwner {
                            Button("Supprimer mon compte", role: .destructive) { askDelete = true }
                        }
                    } footer: {
                        Text("Serveur : \(ServerSettings.urlString)\nMailCleaner pour iPhone \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Compte")
            .refreshable { await reload() }
            .task { await reload() }
            .confirmationDialog("Se déconnecter de MailCleaner ?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) { Task { await app.logout() } }
            }
            .passwordPrompt($askDelete, title: "Supprimer votre compte ?",
                            message: "Votre compte, vos boîtes connectées, vos règles et votre historique seront effacés du serveur. Vos e-mails ne sont pas touchés.",
                            confirm: "Supprimer") { pw in
                Task { await deleteAccount(pw) }
            }
            .sheet(item: Binding(get: { exportURL.map(ExportFile.init) }, set: { if $0 == nil { exportURL = nil } })) { file in
                ShareSheet(items: [file.url])
            }
        }
    }

    private var mfaSummary: String {
        guard let mfa else { return (app.user?.mfa ?? false) ? "Activée" : "Désactivée" }
        guard mfa.enabled else { return "Désactivée" }
        return mfa.methods.map { $0 == "totp" ? "Application" : "E-mail" }.joined(separator: " + ")
    }

    private func row(_ title: String, value: String?, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
            Text(title)
            Spacer(minLength: 8)
            if let value {
                Text(value).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func reload() async {
        await app.refreshMe()
        mfa = try? await APIClient.shared.get("/api/account/mfa")
        billing = try? await APIClient.shared.get("/api/billing")
    }

    private func export() async {
        exporting = true
        defer { exporting = false }
        guard let url = APIClient.shared.url("/api/auth/export") else { return }
        var req = URLRequest(url: url)
        req.setValue("MailCleaner", forHTTPHeaderField: "X-Requested-With")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError(status: 0, message: "Export impossible.") }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("mailcleaner-mes-donnees.json")
            try data.write(to: file, options: .atomic)
            exportURL = file
        } catch {
            app.show(error)
        }
    }

    private func deleteAccount(_ password: String) async {
        do {
            let _: Empty = try await APIClient.shared.post("/api/auth/delete", ["password": password])
            await app.logout()
            app.show("Compte supprimé.", style: .success)
        } catch {
            app.show(error)
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Prénom

struct ProfileNameView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("Prénom", text: $name)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }
            } footer: {
                Text("Utilisé uniquement pour vous saluer dans l'app.")
            }
        }
        .navigationTitle("Prénom")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if busy { ProgressView() } else { Button("Enregistrer") { Task { await save() } } }
            }
        }
        .onAppear { name = app.user?.firstName ?? "" }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            let env: UserEnvelope = try await APIClient.shared.post("/api/auth/profile", ["name": name.trimmingCharacters(in: .whitespaces)])
            if let u = env.user { app.user = u }
            app.show("Prénom enregistré.", style: .success)
            dismiss()
        } catch {
            app.show(error)
        }
    }
}

// MARK: - Mot de passe

struct ChangePasswordView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var problem: String? {
        if new.isEmpty { return nil }
        if let p = Format.passwordProblem(new) { return p }
        if !confirm.isEmpty && confirm != new { return "Les deux mots de passe ne correspondent pas." }
        if new == current { return "Le nouveau mot de passe doit être différent de l'actuel." }
        return nil
    }

    var body: some View {
        Form {
            Section {
                SecureField("Mot de passe actuel", text: $current).textContentType(.password)
            } footer: {
                if app.user?.mustChangePassword == true {
                    Text("Saisissez le mot de passe temporaire donné par l'administrateur.")
                }
            }
            Section {
                SecureField("Nouveau mot de passe", text: $new).textContentType(.newPassword)
                SecureField("Confirmer", text: $confirm).textContentType(.newPassword)
            } footer: {
                PasswordStrength(password: new)
            }
            if let message = error ?? problem {
                Section {
                    Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.footnote)
                }
            }
            Section {
                PrimaryButton(title: "Mettre à jour", busy: busy,
                              disabled: current.isEmpty || new.isEmpty || confirm != new || problem != nil) {
                    Task { await save() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Vos autres appareils seront déconnectés. Celui-ci reste connecté.")
            }
        }
        .navigationTitle("Mot de passe")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: current) { _ in error = nil }
    }

    private func save() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let env: UserEnvelope = try await APIClient.shared.post("/api/auth/password", ["current": current, "new": new])
            if let u = env.user { app.user = u }
            app.show("Mot de passe mis à jour. Vos autres appareils ont été déconnectés.", style: .success)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
