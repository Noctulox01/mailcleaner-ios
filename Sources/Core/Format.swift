import Foundation

enum Format {
    private static let fr = Locale(identifier: "fr_FR")

    static func bytes(_ value: Double?) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(value ?? 0))
    }

    static func number(_ value: Int?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = fr
        return f.string(from: NSNumber(value: value ?? 0)) ?? "\(value ?? 0)"
    }

    static func relative(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "jamais" }
        let f = RelativeDateTimeFormatter()
        f.locale = fr
        f.unitsStyle = .full
        return f.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
    }

    static func date(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "—" }
        let f = DateFormatter()
        f.locale = fr
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    static func dateTime(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "—" }
        let f = DateFormatter()
        f.locale = fr
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    static func plural(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number(n)) \(n > 1 ? (plural ?? singular + "s") : singular)"
    }

    /// Mêmes règles que le serveur (recommandation CNIL) : 8 caractères, 3 types sur 4.
    static func passwordProblem(_ pw: String) -> String? {
        if pw.count < 8 { return "Au moins 8 caractères." }
        let kinds = [pw.range(of: "[a-z]", options: .regularExpression),
                     pw.range(of: "[A-Z]", options: .regularExpression),
                     pw.range(of: "[0-9]", options: .regularExpression),
                     pw.range(of: "[^A-Za-z0-9]", options: .regularExpression)].compactMap { $0 }.count
        if kinds < 3 { return "Utilisez 3 types de caractères : minuscules, majuscules, chiffres, symboles." }
        return nil
    }

    static func isEmail(_ s: String) -> Bool {
        s.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}
