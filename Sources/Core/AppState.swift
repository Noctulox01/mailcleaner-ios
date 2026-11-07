import Foundation
import SwiftUI

/// État global : session, utilisateur connecté, messages éphémères.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case launching
        case loggedOut
        case mfa(MFAChallenge)
        case loggedIn
    }

    @Published var phase: Phase = .launching
    @Published var user: User?
    @Published var config: AppConfig?
    @Published var toast: Toast?
    /// Incrémenté quand les données des boîtes doivent être rechargées (fin d'une tâche, ajout, suppression).
    @Published var dataVersion = 0

    let api = APIClient.shared
    let jobs: JobCenter

    init() {
        jobs = JobCenter()
        jobs.app = self
        api.onSessionExpired = { [weak self] in
            Task { @MainActor in self?.sessionExpired() }
        }
    }

    // MARK: - Démarrage et session

    func boot() async {
        await loadConfig()
        do {
            let env: UserEnvelope = try await api.get("/api/auth/me")
            if let u = env.user { signedIn(u) } else { phase = .loggedOut }
        } catch {
            phase = .loggedOut
            show(error)
        }
    }

    func loadConfig() async {
        config = try? await api.get("/api/config")
    }

    func login(email: String, password: String, remember: Bool) async throws {
        let r: LoginResponse = try await api.post("/api/auth/login",
                                                  ["email": email, "password": password, "remember": remember])
        if let u = r.user {
            signedIn(u)
        } else if r.mfaRequired == true {
            let methods = r.methods ?? []
            phase = .mfa(MFAChallenge(methods: methods,
                                      preferred: r.preferred ?? methods.first ?? "totp",
                                      emailHint: r.emailHint,
                                      hasRecovery: r.recovery ?? false,
                                      remember: remember))
        }
    }

    func register(name: String, email: String, password: String) async throws {
        let env: UserEnvelope = try await api.post("/api/auth/register",
                                                   ["name": name, "email": email, "password": password, "accept_terms": true])
        if let u = env.user { signedIn(u) }
    }

    func sendLoginCode() async throws -> String? {
        let r: CodeSent = try await api.post("/api/auth/mfa/send", ["method": "email"])
        return r.to
    }

    func verifyMFA(method: String, code: String, trustDevice: Bool) async throws {
        let env: UserEnvelope = try await api.post("/api/auth/mfa/verify",
                                                   ["method": method, "code": code, "trust_device": trustDevice])
        if let u = env.user { signedIn(u) }
    }

    func cancelMFA() {
        api.clearCookies()
        phase = .loggedOut
    }

    func logout() async {
        let _: Empty? = try? await api.post("/api/auth/logout")
        api.clearCookies()
        jobs.reset()
        user = nil
        phase = .loggedOut
    }

    func refreshMe() async {
        guard let env: UserEnvelope = try? await api.get("/api/auth/me") else { return }
        if let u = env.user { user = u } else { sessionExpired() }
    }

    private func signedIn(_ u: User) {
        user = u
        phase = .loggedIn
        jobs.resume()
    }

    private func sessionExpired() {
        guard phase == .loggedIn else { return }
        jobs.reset()
        user = nil
        phase = .loggedOut
        show("Votre session a expiré. Reconnectez-vous.", style: .error)
    }

    func dataChanged() { dataVersion += 1 }

    // MARK: - Messages éphémères

    func show(_ text: String, style: Toast.Style = .info) {
        let t = Toast(text: text, style: style)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = t }
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if toast?.id == t.id { withAnimation { toast = nil } }
        }
    }

    func show(_ error: Error) {
        show((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, style: .error)
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case info, success, error }
    let id = UUID()
    let text: String
    let style: Style
}

/// Suivi des tâches de fond du serveur (analyse, suppression, vidage, règles, contacts).
@MainActor
final class JobCenter: ObservableObject {
    @Published private(set) var running: [String: Job] = [:]   // par identifiant de boîte mail
    weak var app: AppState?
    private var pollers: [String: Task<Void, Never>] = [:]

    func job(for mailboxID: String) -> Job? { running[mailboxID] }

    /// Lance une tâche (réponse 202 contenant « job ») et la suit jusqu'au bout.
    @discardableResult
    func start(_ path: String, _ body: [String: Any] = [:]) async throws -> Job {
        let env: JobEnvelope = try await APIClient.shared.post(path, body)
        track(env.job)
        return env.job
    }

    /// Reprend le suivi des tâches encore en cours (après relance de l'app).
    func resume() {
        Task {
            guard let list: JobList = try? await APIClient.shared.get("/api/jobs") else { return }
            for job in list.items where job.isRunning { track(job) }
        }
    }

    func reset() {
        pollers.values.forEach { $0.cancel() }
        pollers.removeAll()
        running.removeAll()
    }

    private func track(_ job: Job) {
        running[job.mailboxId] = job
        pollers[job.id]?.cancel()
        pollers[job.id] = Task { [weak self] in
            var current = job
            while current.isRunning && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let env: JobEnvelope = try? await APIClient.shared.get("/api/jobs/\(job.id)") else { continue }
                current = env.job
                self?.running[job.mailboxId] = current
            }
            guard !Task.isCancelled else { return }
            self?.finished(current)
        }
    }

    private func finished(_ job: Job) {
        pollers[job.id] = nil
        running[job.mailboxId] = nil
        guard let app else { return }
        if job.status == "done" {
            app.show(Self.summary(job), style: .success)
        } else {
            app.show(job.error ?? "La tâche a échoué.", style: .error)
        }
        app.dataChanged()
        Task { await app.refreshMe() }
    }

    private static func summary(_ job: Job) -> String {
        switch job.kind {
        case "scan":
            if let n = job.result?["senders"]?.intValue { return "Analyse terminée : \(n) expéditeurs trouvés." }
            return "Analyse terminée."
        case "delete", "rules":
            if let n = job.deleted { return n == 0 ? "Aucun message à supprimer." : "\(n) message\(n > 1 ? "s" : "") supprimé\(n > 1 ? "s" : "")." }
            return "\(job.label) terminée."
        case "empty":
            if let n = job.deleted { return "\(n) message\(n > 1 ? "s" : "") définitivement supprimé\(n > 1 ? "s" : "")." }
            return "Dossier vidé."
        case "contacts":
            if let n = job.result?["contacts"]?.intValue { return "\(n) contacts protégés." }
            return "Contacts synchronisés."
        default:
            return "\(job.label) terminée."
        }
    }
}
