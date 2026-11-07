import Foundation

// Modèles qui correspondent aux réponses JSON de l'API MailCleaner.
// Les clés serveur sont en snake_case : le décodeur les convertit (last_scan → lastScan).
// Presque tout est optionnel : une évolution du serveur ne doit pas casser l'app.

struct Empty: Decodable {}

// MARK: - Compte

struct User: Decodable, Equatable {
    let id: String
    let email: String
    let name: String?
    let role: String?
    let status: String?
    let createdAt: Double?
    let lastLogin: Double?
    let mustChangePassword: Bool?
    let stats: [String: Double]?
    let billing: Billing?
    let mfa: Bool?

    var isOwner: Bool { role == "admin" }
    var displayName: String { (name?.isEmpty == false ? name : nil) ?? email }
    var firstName: String { (name?.isEmpty == false ? name : nil) ?? "" }
    var deletedCount: Int { Int(stats?["deleted"] ?? 0) }
    var scannedCount: Int { Int(stats?["scanned"] ?? 0) }
    var unsubscribedCount: Int { Int(stats?["unsubscribed"] ?? 0) }
}

struct Billing: Decodable, Equatable {
    let plan: String?
    let status: String?
    let periodEnd: Double?
    let cancelAtPeriodEnd: Bool?
    let interval: String?
    let hasCustomer: Bool?
    let preview: String?
    let license: License?

    var planLabel: String { Plan.label(plan) }
    var isSubscribed: Bool { ["active", "trialing", "past_due"].contains(status ?? "") }
}

struct License: Decodable, Equatable {
    let plan: String?
    let until: Double?
    let lifetime: Bool?
    let active: Bool?
    let activatedAt: Double?
}

struct UserEnvelope: Decodable { let user: User? }

/// Réponse de /api/auth/login : soit l'utilisateur, soit une demande de second facteur.
struct LoginResponse: Decodable {
    let user: User?
    let mfaRequired: Bool?
    let methods: [String]?
    let preferred: String?
    let emailHint: String?
    let recovery: Bool?
}

struct MFAChallenge: Equatable {
    let methods: [String]
    let preferred: String
    let emailHint: String?
    let hasRecovery: Bool
    let remember: Bool
}

// MARK: - Double authentification

struct MFAStatus: Decodable, Equatable {
    let enabled: Bool
    let methods: [String]
    let preferred: String?
    let recoveryLeft: Int?
    let emailAvailable: Bool?
}

struct TOTPSetup: Decodable {
    let secret: String
    let uri: String
    let qrSvg: String?
}

struct MFAEnableReply: Decodable {
    let mfa: MFAStatus
    let recoveryCodes: [String]?
}

struct MFAReply: Decodable { let mfa: MFAStatus }
struct RecoveryReply: Decodable { let recoveryCodes: [String]; let mfa: MFAStatus }
struct CodeSent: Decodable { let sent: Bool?; let to: String? }

// MARK: - Boîtes mail

struct Mailbox: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let provider: String
    let email: String
    let auth: String?
    let createdAt: Double?
    let lastScan: ScanSummary?
    let stats: [String: Double]?

    var providerInfo: Provider { Provider(rawValue: provider) ?? .icloud }
    var deletedCount: Int { Int(stats?["deleted"] ?? 0) }

    static func == (a: Mailbox, b: Mailbox) -> Bool { a.id == b.id && a.lastScan == b.lastScan && a.stats == b.stats }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct ScanSummary: Decodable, Equatable {
    let ts: Double?
    let scanned: Int?
    let inboxTotal: Int?
    let senders: Int?
    let newsletters: Int?
    let contacts: Int?
}

struct MailboxList: Decodable { let items: [Mailbox] }
struct MailboxEnvelope: Decodable { let mailbox: Mailbox }

struct Overview: Decodable, Equatable {
    let inbox: Int?
    let trash: Int?
    let junk: Int?
    let trashName: String?
    let junkName: String?
}

enum Provider: String, CaseIterable, Identifiable {
    case icloud, gmail, outlook
    var id: String { rawValue }

    var label: String {
        switch self {
        case .icloud: return "iCloud"
        case .gmail: return "Gmail"
        case .outlook: return "Outlook"
        }
    }
    var symbol: String {
        switch self {
        case .icloud: return "icloud.fill"
        case .gmail: return "envelope.fill"
        case .outlook: return "tray.full.fill"
        }
    }
    /// Page officielle où l'on crée un mot de passe d'application.
    var appPasswordURL: URL? {
        switch self {
        case .icloud: return URL(string: "https://account.apple.com")
        case .gmail: return URL(string: "https://myaccount.google.com/apppasswords")
        case .outlook: return URL(string: "https://account.microsoft.com/security")
        }
    }
    var steps: [String] {
        switch self {
        case .icloud:
            return ["Ouvrez account.apple.com et connectez-vous.",
                    "Allez dans « Connexion et sécurité » → « Mots de passe pour app ».",
                    "Créez un mot de passe nommé « MailCleaner ».",
                    "Copiez-le et collez-le ci-dessous (pas votre mot de passe Apple)."]
        case .gmail:
            return ["Activez la validation en deux étapes sur votre compte Google.",
                    "Ouvrez myaccount.google.com/apppasswords.",
                    "Créez un mot de passe nommé « MailCleaner ».",
                    "Copiez les 16 lettres et collez-les ci-dessous."]
        case .outlook:
            return ["Ouvrez account.microsoft.com → Sécurité.",
                    "Activez la vérification en deux étapes.",
                    "Créez un « mot de passe d'application ».",
                    "Copiez-le et collez-le ci-dessous."]
        }
    }
}

// MARK: - Analyse et expéditeurs

struct ScanEnvelope: Decodable { let scan: Scan? }

struct Scan: Decodable, Equatable {
    let ts: Double?
    let scanned: Int?
    let inboxTotal: Int?
    let senders: [Sender]
}

struct Sender: Decodable, Identifiable, Equatable, Hashable {
    let email: String
    let name: String?
    let count: Int
    let size: Double?
    let last: Double?
    let subjects: [String]?
    let unsubHttp: String?
    let unsubMailto: String?
    let oneClick: Bool?
    let newsletter: Bool?
    let unsubscribed: Bool?

    var id: String { email }
    var displayName: String { (name?.isEmpty == false ? name : nil) ?? email }
    var canUnsubscribe: Bool { (unsubHttp ?? unsubMailto) != nil && unsubscribed != true }
    var domain: String { email.split(separator: "@").last.map(String.init) ?? email }
}

struct UnsubscribeReply: Decodable {
    let done: Bool?
    let url: String?
    let warning: String?
}

// MARK: - Tâches de fond

struct Job: Decodable, Identifiable, Equatable {
    let id: String
    let mailboxId: String
    let mailboxEmail: String?
    let kind: String
    let label: String
    let status: String
    let progress: Int?
    let message: String?
    let error: String?
    let result: [String: JSONValue]?
    let startedAt: Double?
    let finishedAt: Double?

    var isRunning: Bool { status == "running" }
    var fraction: Double { Double(progress ?? 0) / 100 }
    var deleted: Int? { result?["deleted"]?.intValue }
}

struct JobEnvelope: Decodable { let job: Job }
struct JobList: Decodable { let items: [Job] }

/// Valeur JSON quelconque (résultats de tâches dont la forme varie).
enum JSONValue: Decodable, Equatable {
    case number(Double), string(String), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }
    var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
}

// MARK: - Règles

struct Rules: Decodable, Equatable {
    let blocked: [String]
    let keywords: [String]
    let protected: [String]
    let contacts: [String]?
    let contactsAuto: Bool?
    let contactsSyncedAt: Double?
}

struct RulesEnvelope: Decodable { let rules: Rules }

enum RuleList: String, CaseIterable, Identifiable {
    case blocked, keywords, protected
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blocked: return "Expéditeurs bloqués"
        case .keywords: return "Mots-clés"
        case .protected: return "Expéditeurs protégés"
        }
    }
    var help: String {
        switch self {
        case .blocked: return "Leurs messages sont supprimés quand vous appliquez les règles. Adresse complète ou domaine (ex. promo.fr)."
        case .keywords: return "Un message dont l'objet contient l'un de ces mots est supprimé."
        case .protected: return "Jamais supprimés, même s'ils correspondent à une autre règle."
        }
    }
    var placeholder: String {
        switch self {
        case .blocked: return "newsletter@exemple.fr ou exemple.fr"
        case .keywords: return "promotion, soldes…"
        case .protected: return "banque.fr, maman@exemple.fr…"
        }
    }
    var symbol: String {
        switch self {
        case .blocked: return "hand.raised.fill"
        case .keywords: return "textformat"
        case .protected: return "checkmark.shield.fill"
        }
    }
}

// MARK: - Activité

struct ActivityItem: Decodable, Identifiable, Equatable {
    let ts: Double
    let text: String
    let kind: String?
    var id: String { "\(ts)-\(text.hashValue)" }
}

struct ActivityList: Decodable { let items: [ActivityItem] }

// MARK: - Abonnement

struct BillingInfo: Decodable {
    let enabled: Bool?
    let ready: Bool?
    let provider: String?
    let keysMode: Bool?
    let testMode: Bool?
    let plans: [String: Plan]?
    let trialDays: Int?
    let billing: Billing?
}

struct Plan: Decodable {
    let name: String?
    let features: [String]?
    let maxMailboxes: Int?
    let scanLimit: Int?
    let members: Int?
    let prices: [String: Price]?

    static func label(_ key: String?) -> String {
        switch key {
        case "premium": return "Premium"
        case "family": return "Famille"
        case "free", nil: return "Gratuit"
        default: return key!.capitalized
        }
    }
}

struct Price: Decodable { let amount: Double? }
struct URLReply: Decodable { let url: String? }
struct BillingReply: Decodable { let billing: Billing? }
struct LicenseReply: Decodable { let user: User? }

struct AppConfig: Decodable {
    let msOauth: Bool?
    let scanLimit: Int?
    let registration: String?
    let billing: Bool?
}

struct MicrosoftStart: Decodable {
    let flowId: String
    let userCode: String
    let verificationUri: String?
    let interval: Int?
}

struct MicrosoftPoll: Decodable {
    let status: String?
    let mailbox: Mailbox?
}
