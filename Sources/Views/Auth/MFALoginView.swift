import SwiftUI

/// Second facteur à la connexion : application d'authentification, code par e-mail ou code de secours.
struct MFALoginView: View {
    @EnvironmentObject private var app: AppState
    let challenge: MFAChallenge

    @State private var method: String = ""
    @State private var code = ""
    @State private var trust = true
    @State private var busy = false
    @State private var sending = false
    @State private var sentTo: String?
    @State private var error: String?
    @FocusState private var focused: Bool

    private var methods: [String] { challenge.methods + (challenge.hasRecovery ? ["recovery"] : []) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Brand.gradient)
                        .padding(.top, 12)
                    Text("Vérification en deux étapes")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if methods.count > 1 {
                        Picker("Méthode", selection: $method) {
                            ForEach(methods, id: \.self) { m in Text(Self.label(m)).tag(m) }
                        }
                        .pickerStyle(.segmented)
                    }

                    TextField(method == "recovery" ? "ABCD-EFGH" : "123456", text: $code)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .keyboardType(method == "recovery" ? .asciiCapable : .numberPad)
                        .textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .frame(height: 64)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: code) { value in
                            // Validation automatique dès que les 6 chiffres sont saisis.
                            if method != "recovery" && value.filter(\.isNumber).count == 6 && !busy { verify() }
                        }

                    if method == "email" {
                        Button {
                            Task { await send() }
                        } label: {
                            if sending { ProgressView() } else { Text(sentTo == nil ? "Envoyer le code" : "Renvoyer un code") }
                        }
                        .disabled(sending)
                    }

                    Toggle("Faire confiance à cet iPhone pendant 30 jours", isOn: $trust)
                        .font(.subheadline)

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(title: "Vérifier", busy: busy, disabled: code.trimmingCharacters(in: .whitespaces).isEmpty) {
                        verify()
                    }
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { app.cancelMFA() }
                }
            }
        }
        .onAppear {
            method = challenge.preferred
            focused = true
        }
        .onChange(of: method) { m in
            code = ""
            error = nil
            if m == "email" && sentTo == nil { Task { await send() } }
        }
    }

    private var hint: String {
        switch method {
        case "email":
            if let sentTo { return "Code envoyé à \(sentTo). Il expire dans 10 minutes." }
            return "Un code à 6 chiffres va être envoyé à \(challenge.emailHint ?? "votre adresse e-mail")."
        case "recovery":
            return "Saisissez l'un de vos codes de secours. Chaque code ne sert qu'une fois."
        default:
            return "Ouvrez votre application d'authentification et saisissez le code à 6 chiffres affiché pour MailCleaner."
        }
    }

    static func label(_ m: String) -> String {
        switch m {
        case "totp": return "Application"
        case "email": return "E-mail"
        case "recovery": return "Secours"
        default: return m
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            sentTo = try await app.sendLoginCode() ?? challenge.emailHint
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() {
        let value = code.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await app.verifyMFA(method: method, code: value, trustDevice: trust)
            } catch {
                self.error = error.localizedDescription
                code = ""
                if let e = error as? APIError, e.message.contains("reconnectez") || e.message.contains("expirée") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    app.cancelMFA()
                }
            }
        }
    }
}
