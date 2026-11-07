import SwiftUI

struct MFASettingsView: View {
    @EnvironmentObject private var app: AppState
    @Binding var status: MFAStatus?

    @State private var setup: SetupKind?
    @State private var recoveryCodes: RecoveryCodes?
    @State private var disabling: String?
    @State private var askRecovery = false
    @State private var busy = false

    enum SetupKind: String, Identifiable { case totp, email; var id: String { rawValue } }
    struct RecoveryCodes: Identifiable { let codes: [String]; var id: String { codes.joined() } }

    var body: some View {
        List {
            Section {
                Label {
                    Text(status?.enabled == true
                         ? "Un code vous est demandé en plus du mot de passe lorsque vous vous connectez sur un nouvel appareil."
                         : "Protégez votre compte : en plus du mot de passe, un code à usage unique vous sera demandé à la connexion.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: status?.enabled == true ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(status?.enabled == true ? .green : .orange)
                }
            }

            Section("Méthodes") {
                methodRow("totp", title: "Application d'authentification",
                          detail: "Google Authenticator, Microsoft Authenticator, Authy, 1Password… Fonctionne sans réseau. Recommandé.",
                          symbol: "iphone.gen3", available: true)
                methodRow("email", title: "Code par e-mail",
                          detail: status?.emailAvailable == false
                              ? "L'envoi d'e-mails n'est pas encore configuré sur ce serveur."
                              : "Un code envoyé à votre adresse à chaque connexion.",
                          symbol: "envelope.fill", available: status?.emailAvailable != false)
            }

            if let status, status.methods.count > 1 {
                Section {
                    Picker("Méthode proposée en premier", selection: Binding(get: { status.preferred ?? status.methods[0] },
                                                                           set: { m in Task { await setPreferred(m) } })) {
                        ForEach(status.methods, id: \.self) { m in Text(m == "totp" ? "Application" : "E-mail").tag(m) }
                    }
                }
            }

            if status?.enabled == true {
                Section {
                    HStack {
                        Text("Codes de secours restants")
                        Spacer()
                        Text("\(status?.recoveryLeft ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Button("Générer de nouveaux codes de secours") { askRecovery = true }
                    Button("Oublier les appareils de confiance") { Task { await forgetDevices() } }
                } header: {
                    Text("Secours")
                } footer: {
                    Text("Les codes de secours permettent de vous connecter si vous perdez votre téléphone.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Double authentification")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if status == nil { ProgressView() } }
        .task { await load() }
        .sheet(item: $setup) { kind in
            MFASetupSheet(kind: kind) { reply in
                status = reply.mfa
                setup = nil
                Task { await app.refreshMe() }
                app.show("Double authentification activée.", style: .success)
                if let codes = reply.recoveryCodes, !codes.isEmpty {
                    // Laisse la feuille se fermer avant d'afficher les codes.
                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        recoveryCodes = RecoveryCodes(codes: codes)
                    }
                }
            }
        }
        .sheet(item: $recoveryCodes) { RecoveryCodesSheet(codes: $0.codes) }
        .passwordPrompt(Binding(get: { disabling != nil }, set: { if !$0 { disabling = nil } }),
                        title: "Désactiver cette méthode ?",
                        message: "Votre compte sera moins protégé. Confirmez avec votre mot de passe.",
                        confirm: "Désactiver") { pw in
            if let m = disabling { Task { await disable(m, password: pw) } }
        }
        .passwordPrompt($askRecovery, title: "Nouveaux codes de secours ?",
                        message: "Les anciens codes ne fonctionneront plus. Confirmez avec votre mot de passe.") { pw in
            Task { await regenerate(password: pw) }
        }
    }

    private func methodRow(_ method: String, title: String, detail: String, symbol: String, available: Bool) -> some View {
        let enabled = status?.methods.contains(method) == true
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.body.weight(.semibold))
                    if enabled {
                        Text("Activée")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(.green)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Group {
                    if enabled {
                        Button("Désactiver", role: .destructive) { disabling = method }
                    } else if available {
                        Button("Activer") { setup = SetupKind(rawValue: method) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do { status = try await APIClient.shared.get("/api/account/mfa") } catch { app.show(error) }
    }

    private func setPreferred(_ m: String) async {
        do {
            let r: MFAReply = try await APIClient.shared.post("/api/account/mfa/preferred", ["method": m])
            status = r.mfa
        } catch { app.show(error) }
    }

    private func disable(_ method: String, password: String) async {
        do {
            let r: MFAReply = try await APIClient.shared.post("/api/account/mfa/disable", ["method": method, "password": password])
            status = r.mfa
            await app.refreshMe()
            app.show("Méthode désactivée.", style: .success)
        } catch { app.show(error) }
    }

    private func regenerate(password: String) async {
        do {
            let r: RecoveryReply = try await APIClient.shared.post("/api/account/mfa/recovery", ["password": password])
            status = r.mfa
            recoveryCodes = RecoveryCodes(codes: r.recoveryCodes)
        } catch { app.show(error) }
    }

    private func forgetDevices() async {
        do {
            let _: Empty = try await APIClient.shared.post("/api/account/devices/forget")
            app.show("Appareils de confiance oubliés.", style: .success)
        } catch { app.show(error) }
    }
}

/// Mise en place d'une méthode : QR code (application) ou code reçu par e-mail.
struct MFASetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let kind: MFASettingsView.SetupKind
    let onEnabled: (MFAEnableReply) -> Void

    @State private var totp: TOTPSetup?
    @State private var sentTo: String?
    @State private var code = ""
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if loading {
                        ProgressView().padding(60)
                    } else if kind == .totp, let totp {
                        totpContent(totp)
                    } else if kind == .email {
                        Image(systemName: "envelope.badge.fill").font(.system(size: 48)).foregroundStyle(Brand.accent)
                        Text(sentTo.map { "Code envoyé à \($0). Il expire dans 10 minutes." } ?? "Envoi du code…")
                            .font(.subheadline).multilineTextAlignment(.center)
                    }

                    if !loading && (totp != nil || sentTo != nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kind == .totp ? "3. Saisissez le code affiché par l'application" : "Saisissez le code reçu")
                                .font(.subheadline.weight(.semibold))
                            TextField("123456", text: $code)
                                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .focused($focused)
                                .frame(height: 62)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .onChange(of: code) { v in
                                    if v.filter(\.isNumber).count == 6 && !busy { Task { await confirm() } }
                                }
                        }
                        PrimaryButton(title: "Confirmer", busy: busy, disabled: code.filter(\.isNumber).count != 6) {
                            Task { await confirm() }
                        }
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(kind == .totp ? "Application d'authentification" : "Code par e-mail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
        .task { await start() }
    }

    @ViewBuilder
    private func totpContent(_ t: TOTPSetup) -> some View {
        // Sur iPhone, un lien otpauth:// est souvent pris par l'app « Mots de passe » d'iOS et non par
        // Google Authenticator : la méthode fiable est de copier la clé et de la coller dans l'application.
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Copiez la clé").font(.subheadline.weight(.semibold))
            HStack {
                Text(grouped(t.secret))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer()
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                UIPasteboard.general.string = t.secret
                copied = true
            } label: {
                Label(copied ? "Clé copiée" : "Copier la clé", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 6) {
            Text("2. Ajoutez-la dans Google Authenticator").font(.subheadline.weight(.semibold))
            Text("Touchez « + », puis « Saisir une clé de configuration ». Nom : MailCleaner. Collez la clé. Type : « Basé sur l'heure ». Validez.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Text("Vous aviez déjà ajouté MailCleaner ? Supprimez l'ancienne entrée : seule celle-ci est valable.")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        DisclosureGroup("Autres méthodes : QR code, ajout direct") {
            VStack(spacing: 14) {
                Text("Pour scanner avec un autre téléphone ou une tablette :")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                QRCodeView(text: t.uri, size: 210)
                if let url = URL(string: t.uri) {
                    Button {
                        openURL(url) { accepted in
                            if !accepted { error = "Aucune application d'authentification ne s'est ouverte : utilisez « Copier la clé »." }
                        }
                    } label: {
                        Label("Ajouter sur cet iPhone en un geste", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Text("Ouvre l'application d'authentification par défaut d'iOS (souvent « Mots de passe »), pas forcément Google Authenticator.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
    }

    private func grouped(_ s: String) -> String {
        stride(from: 0, to: s.count, by: 4).map { i -> String in
            let start = s.index(s.startIndex, offsetBy: i)
            let end = s.index(start, offsetBy: min(4, s.count - i))
            return String(s[start..<end])
        }.joined(separator: " ")
    }

    private func start() async {
        loading = true
        defer { loading = false }
        do {
            if kind == .totp {
                totp = try await APIClient.shared.post("/api/account/mfa/totp/setup")
            } else {
                let r: CodeSent = try await APIClient.shared.post("/api/account/mfa/email/setup")
                sentTo = r.to ?? "votre adresse"
            }
            focused = kind == .email
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func confirm() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let path = kind == .totp ? "/api/account/mfa/totp/confirm" : "/api/account/mfa/email/confirm"
            let reply: MFAEnableReply = try await APIClient.shared.post(path, ["code": code.filter(\.isNumber)])
            onEnabled(reply)
        } catch {
            self.error = error.localizedDescription
            code = ""
        }
    }
}

/// Affiche les codes de secours (une seule fois) avec copie et partage.
struct RecoveryCodesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let codes: [String]
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "key.horizontal.fill").font(.system(size: 44)).foregroundStyle(.orange)
                    Text("Gardez ces codes en lieu sûr (gestionnaire de mots de passe, papier). Ils permettent de vous connecter si vous perdez votre téléphone. Chaque code ne sert qu'une fois, et ils ne seront plus affichés.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(codes, id: \.self) { c in
                            Text(c)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .textSelection(.enabled)
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = codes.joined(separator: "\n")
                            copied = true
                        } label: {
                            Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        ShareLink(item: "MailCleaner — codes de secours\n\n" + codes.joined(separator: "\n")) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    PrimaryButton(title: "C'est noté") { dismiss() }
                }
                .padding(20)
            }
            .navigationTitle("Codes de secours")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}
