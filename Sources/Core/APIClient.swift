import Foundation
import CryptoKit

/// Erreur renvoyée par le serveur (message déjà rédigé en français par l'API) ou par le réseau.
struct APIError: LocalizedError {
    let status: Int
    let message: String
    var upgrade: Bool = false

    var errorDescription: String? { message }
    /// 401 « Session expirée » uniquement : un mauvais mot de passe renvoie aussi 401 et ne doit pas déconnecter.
    var isSessionExpired: Bool { status == 401 && message.hasPrefix("Session expirée") }
    var isNetwork: Bool { status == 0 }
}

/// Adresse du serveur MailCleaner, modifiable depuis l'écran de connexion.
enum ServerSettings {
    static let defaultURL = "http://192.168.137.1:5002"
    private static let key = "serverURL"

    static var urlString: String {
        get { UserDefaults.standard.string(forKey: key) ?? defaultURL }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var url: URL { URL(string: urlString) ?? URL(string: defaultURL)! }

    /// « 192.168.1.20:5002/app » → « http://192.168.1.20:5002 ».
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        guard var comps = URLComponents(string: s), comps.host?.isEmpty == false else { return nil }
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        return comps.string
    }
}

/// Client de l'API : cookie de session, en-tête anti-CSRF, décodage JSON, erreurs lisibles.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    /// Appelé (sur le thread principal) quand le serveur signale une session expirée.
    var onSessionExpired: (() -> Void)?

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared            // le cookie de session survit aux relancements de l'app
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 45
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try await request("GET", path, body: nil, retryShield: true)
    }

    func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        try await request("POST", path, body: body, retryShield: true)
    }

    func url(_ path: String) -> URL? { URL(string: path, relativeTo: ServerSettings.url)?.absoluteURL }

    func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]?, retryShield: Bool) async throws -> T {
        guard let url = url(path) else { throw APIError(status: 0, message: "Adresse du serveur invalide.") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        // Le serveur refuse toute écriture sans cet en-tête (protection contre les requêtes d'autres sites).
        req.setValue("MailCleaner", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("MailCleaner-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: req)
        } catch let e as URLError {
            throw APIError(status: 0, message: Self.describe(e))
        } catch {
            throw APIError(status: 0, message: error.localizedDescription)
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if (200..<300).contains(status) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError(status: status, message: "Réponse inattendue du serveur. Mettez le serveur et l'app à jour.")
            }
        }

        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (payload?["error"] as? String) ?? Self.fallback(status)

        // Pic de trafic : le serveur demande une preuve de calcul avant d'accepter les visiteurs non connectés.
        if status == 403, payload?["shield"] as? Bool == true, retryShield {
            try await Shield.solve(using: self)
            return try await request(method, path, body: body, retryShield: false)
        }

        let error = APIError(status: status, message: message, upgrade: payload?["upgrade"] as? Bool == true)
        if error.isSessionExpired {
            await MainActor.run { self.onSessionExpired?() }
        }
        throw error
    }

    func clearCookies() {
        let storage = HTTPCookieStorage.shared
        guard let host = ServerSettings.url.host else { return }
        for cookie in storage.cookies ?? [] where cookie.domain.contains(host) && cookie.name != "mc_device" {
            storage.deleteCookie(cookie)
        }
    }

    private static func describe(_ e: URLError) -> String {
        let server = ServerSettings.urlString
        switch e.code {
        case .notConnectedToInternet:
            return "Pas de connexion réseau. Vérifiez le Wi-Fi."
        case .cannotFindHost, .dnsLookupFailed:
            return "Serveur introuvable (\(server)). Vérifiez l'adresse dans les réglages du serveur."
        case .cannotConnectToHost, .networkConnectionLost:
            return "Le serveur ne répond pas (\(server)). Est-il lancé, et le téléphone est-il sur le même réseau ?"
        case .timedOut:
            return "Le serveur met trop de temps à répondre. Réessayez."
        case .appTransportSecurityRequiresSecureConnection:
            return "Connexion non sécurisée refusée par iOS."
        default:
            return e.localizedDescription
        }
    }

    private static func fallback(_ status: Int) -> String {
        switch status {
        case 404: return "Fonction introuvable sur ce serveur : mettez-le à jour."
        case 429: return "Trop de tentatives. Patientez une minute."
        case 500...599: return "Le serveur a rencontré une erreur. Réessayez."
        default: return "Erreur \(status)."
        }
    }
}

/// Vérification anti-afflux : trouver un nombre tel que SHA-256("jeton:nombre") commence par N bits à zéro.
/// Le calcul (1 à 2 s) se fait hors du thread principal.
enum Shield {
    private struct Challenge: Decodable { let challenge: String; let difficulty: Int }

    static func solve(using api: APIClient) async throws {
        let ch: Challenge = try await api.request("GET", "/api/shield/challenge", body: nil, retryShield: false)
        let token = ch.challenge
        let difficulty = ch.difficulty
        let counter = await Task.detached(priority: .userInitiated) { () -> Int in
            var i = 0
            while true {
                let digest = SHA256.hash(data: Data("\(token):\(i)".utf8))
                if leadingZeroBits(digest) >= difficulty { return i }
                i += 1
            }
        }.value
        let _: Empty = try await api.request("POST", "/api/shield/verify",
                                             body: ["challenge": token, "counter": String(counter)], retryShield: false)
    }

    static func leadingZeroBits(_ digest: SHA256.Digest) -> Int {
        var bits = 0
        for byte in digest {
            if byte == 0 { bits += 8; continue }
            bits += byte.leadingZeroBitCount
            break
        }
        return bits
    }
}
