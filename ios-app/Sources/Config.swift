import Foundation

/// Configuration de l'app. Pour changer de serveur, modifie `siteURL` ci-dessous.
enum Config {
    /// Page ouverte au lancement. On vise directement l'application (écran de connexion),
    /// pas la page vitrine. Change l'URL ici si tu testes en local.
    static let siteURL = URL(string: "https://mailcleaner.fr/app")!

    /// Hôte "interne" : tout ce qui est sur ce domaine reste dans l'app.
    /// Les liens vers d'autres domaines s'ouvrent dans Safari.
    static let internalHost = "mailcleaner.fr"
}
