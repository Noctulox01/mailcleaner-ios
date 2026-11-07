import SwiftUI
import AVKit

/// Ajout d'une boîte mail : fournisseur, adresse, mot de passe d'application (avec guide vidéo).
struct AddMailboxView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var provider: Provider = .icloud
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showGuide = false
    @State private var msFlow: MicrosoftStart?

    private var useMicrosoft: Bool { provider == .outlook && app.config?.msOauth == true }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        ForEach(Provider.allCases) { p in
                            Button { withAnimation(.spring(response: 0.3)) { provider = p; error = nil } } label: {
                                VStack(spacing: 8) {
                                    ProviderBadge(provider: p, size: 44)
                                    Text(p.label).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(provider == p ? Brand.accent : Color(.separator),
                                                      lineWidth: provider == p ? 2.5 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(provider == p ? .isSelected : [])
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: {
                    Text("Fournisseur")
                }

                Section("Adresse e-mail") {
                    TextField("vous@\(provider == .gmail ? "gmail.com" : provider == .outlook ? "outlook.fr" : "icloud.com")", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if useMicrosoft {
                    Section {
                        if let msFlow {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("1. Copiez ce code :").font(.subheadline)
                                Text(msFlow.userCode)
                                    .font(.system(.title, design: .monospaced).weight(.bold))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity)
                                Button {
                                    UIPasteboard.general.string = msFlow.userCode
                                    if let u = URL(string: msFlow.verificationUri ?? "https://microsoft.com/devicelogin") { openURL(u) }
                                } label: { Label("Copier et ouvrir Microsoft", systemImage: "arrow.up.right.square") }
                                Text("2. Collez-le sur la page Microsoft et acceptez. L'app détecte la connexion toute seule.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                HStack { ProgressView(); Text("En attente de Microsoft…").foregroundStyle(.secondary).font(.footnote) }
                            }
                        } else {
                            Text("Outlook se connecte avec votre compte Microsoft : pas de mot de passe à copier.")
                                .font(.footnote)
                        }
                    } header: { Text("Connexion Microsoft") }
                } else {
                    Section {
                        SecureField("Mot de passe d'application", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Mot de passe d'application")
                    } footer: {
                        Text("Ce n'est pas votre mot de passe habituel : c'est un code spécial créé pour MailCleaner, que vous pouvez révoquer à tout moment.")
                    }

                    Section {
                        Button { showGuide = true } label: {
                            Label("Voir la vidéo explicative", systemImage: "play.rectangle.fill")
                        }
                        ForEach(Array(provider.steps.enumerated()), id: \.offset) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(item.offset + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Brand.accent))
                                Text(item.element).font(.subheadline)
                            }
                        }
                        if let url = provider.appPasswordURL {
                            Link(destination: url) {
                                Label("Ouvrir la page \(provider.label)", systemImage: "arrow.up.right.square")
                            }
                        }
                    } header: {
                        Text("Comment l'obtenir ?")
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Ajouter une boîte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button(useMicrosoft ? "Continuer" : "Connecter") { submit() }
                            .disabled(!canSubmit)
                    }
                }
            }
            .sheet(isPresented: $showGuide) { GuideVideoView(provider: provider) }
            .interactiveDismissDisabled(busy || msFlow != nil)
        }
    }

    private var canSubmit: Bool {
        Format.isEmail(email.trimmingCharacters(in: .whitespaces)) && (useMicrosoft ? msFlow == nil : !password.isEmpty)
    }

    private func submit() {
        guard canSubmit else { return }
        busy = true
        error = nil
        let mail = email.trimmingCharacters(in: .whitespaces).lowercased()
        Task {
            defer { busy = false }
            do {
                if useMicrosoft {
                    let flow: MicrosoftStart = try await APIClient.shared.post("/api/oauth/microsoft/start", ["email": mail])
                    msFlow = flow
                    busy = false
                    try await pollMicrosoft(flow)
                } else {
                    let _: MailboxEnvelope = try await APIClient.shared.post("/api/mailboxes",
                                                                             ["provider": provider.rawValue, "email": mail, "password": password])
                    done()
                }
            } catch {
                self.error = error.localizedDescription
                msFlow = nil
            }
        }
    }

    private func pollMicrosoft(_ flow: MicrosoftStart) async throws {
        let wait = UInt64(max(flow.interval ?? 5, 2)) * 1_000_000_000
        while msFlow != nil {
            try await Task.sleep(nanoseconds: wait)
            let r: MicrosoftPoll = try await APIClient.shared.post("/api/oauth/microsoft/poll", ["flow_id": flow.flowId])
            if r.status == "done" { done(); return }
        }
    }

    private func done() {
        app.show("Boîte mail connectée.", style: .success)
        app.dataChanged()
        dismiss()
    }
}

/// Vidéo explicative hébergée par le serveur (media/guides/<fournisseur>-fr.mp4).
struct GuideVideoView: View {
    @Environment(\.dismiss) private var dismiss
    let provider: Provider
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ProgressView().frame(height: 200)
                }
                Text("Suivez la vidéo, puis revenez coller le mot de passe dans MailCleaner.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(16)
            .navigationTitle("Mot de passe \(provider.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .onAppear {
            if let url = APIClient.shared.url("/media/guides/\(provider.rawValue)-fr.mp4") {
                let p = AVPlayer(url: url)
                player = p
                p.play()
            }
        }
        .onDisappear { player?.pause() }
    }
}
