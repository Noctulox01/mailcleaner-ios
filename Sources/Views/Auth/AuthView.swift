import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var app: AppState
    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var remember = true
    @State private var acceptTerms = false
    @State private var busy = false
    @State private var error: String?
    @State private var showServer = false
    @FocusState private var focus: Field?

    enum Mode { case login, register }
    enum Field { case name, email, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    Picker("", selection: $mode) {
                        Text("Connexion").tag(Mode.login)
                        Text("Créer un compte").tag(Mode.register)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in error = nil }

                    VStack(spacing: 14) {
                        if mode == .register {
                            LabeledField(label: "Prénom (facultatif)") {
                                TextField("Votre prénom", text: $name)
                                    .textContentType(.givenName)
                                    .focused($focus, equals: .name)
                                    .submitLabel(.next)
                                    .onSubmit { focus = .email }
                            }
                        }
                        LabeledField(label: "Adresse e-mail") {
                            TextField("vous@exemple.fr", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                        }
                        LabeledField(label: "Mot de passe") {
                            SecureField(mode == .login ? "Votre mot de passe" : "8 caractères minimum", text: $password)
                                .textContentType(mode == .login ? .password : .newPassword)
                                .focused($focus, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { submit() }
                        }
                        if mode == .register {
                            PasswordStrength(password: password)
                            Toggle(isOn: $acceptTerms) {
                                Text("J'accepte les conditions d'utilisation et la politique de confidentialité.")
                                    .font(.footnote)
                            }
                            .toggleStyle(CheckboxStyle())
                        } else {
                            Toggle("Rester connecté", isOn: $remember)
                                .font(.subheadline)
                        }
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }

                    PrimaryButton(title: mode == .login ? "Se connecter" : "Créer mon compte",
                                  busy: busy, disabled: !canSubmit) { submit() }

                    if mode == .login {
                        Text("Mot de passe oublié ? Demandez au propriétaire du serveur un mot de passe temporaire.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showServer = true } label: { Image(systemName: "server.rack") }
                        .accessibilityLabel("Adresse du serveur")
                }
            }
            .sheet(isPresented: $showServer) { ServerSettingsView() }
            .animation(.default, value: mode)
            .animation(.default, value: error)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            BrandMark(size: 76)
            Text("MailCleaner").font(.largeTitle.weight(.bold))
            Text("Votre boîte mail, enfin rangée.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var canSubmit: Bool {
        Format.isEmail(email.trimmingCharacters(in: .whitespaces)) && !password.isEmpty
            && (mode == .login || (acceptTerms && Format.passwordProblem(password) == nil))
    }

    private func submit() {
        guard canSubmit, !busy else { return }
        focus = nil
        busy = true
        error = nil
        let mail = email.trimmingCharacters(in: .whitespaces).lowercased()
        Task {
            defer { busy = false }
            do {
                if mode == .login {
                    try await app.login(email: mail, password: password, remember: remember)
                } else {
                    try await app.register(name: name.trimmingCharacters(in: .whitespaces), email: mail, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Indicateur des règles du mot de passe, mis à jour à la frappe.
struct PasswordStrength: View {
    let password: String

    private var checks: [(String, Bool)] {
        [("8 caractères minimum", password.count >= 8),
         ("Minuscule", password.range(of: "[a-z]", options: .regularExpression) != nil),
         ("Majuscule", password.range(of: "[A-Z]", options: .regularExpression) != nil),
         ("Chiffre", password.range(of: "[0-9]", options: .regularExpression) != nil),
         ("Symbole", password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Au moins 8 caractères et 3 types parmi : minuscules, majuscules, chiffres, symboles.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(checks, id: \.0) { check in
                    Image(systemName: check.1 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(check.1 ? Color.green : Color.secondary)
                        .accessibilityLabel("\(check.0) : \(check.1 ? "oui" : "non")")
                }
                Spacer()
                Text(Format.passwordProblem(password) == nil ? "Mot de passe valide" : "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Brand.accent : .secondary)
                configuration.label
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Réglage de l'adresse du serveur (ex. le PC sur son point d'accès : http://192.168.137.1:5002).
struct ServerSettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var address = ServerSettings.urlString
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.137.1:5002", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Adresse du serveur")
                } footer: {
                    Text("L'adresse du PC qui fait tourner MailCleaner. Avec le point d'accès sans fil de Windows, c'est en général http://192.168.137.1:5002.")
                }
                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Tester la connexion")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing)
                    if let result {
                        Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.ok ? .green : .red)
                            .font(.footnote)
                    }
                }
                Section {
                    Button("Rétablir l'adresse par défaut") { address = ServerSettings.defaultURL }
                }
            }
            .navigationTitle("Serveur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.disabled(ServerSettings.normalize(address) == nil)
                }
            }
        }
    }

    private func save() {
        guard let url = ServerSettings.normalize(address) else { return }
        ServerSettings.urlString = url
        dismiss()
        Task { await app.boot() }
    }

    private func test() async {
        guard let url = ServerSettings.normalize(address) else {
            result = (false, "Adresse invalide.")
            return
        }
        testing = true
        defer { testing = false }
        let previous = ServerSettings.urlString
        ServerSettings.urlString = url
        defer { ServerSettings.urlString = previous }
        do {
            let _: AppConfig = try await APIClient.shared.get("/api/config")
            result = (true, "Serveur MailCleaner joignable.")
        } catch {
            result = (false, error.localizedDescription)
        }
    }
}
