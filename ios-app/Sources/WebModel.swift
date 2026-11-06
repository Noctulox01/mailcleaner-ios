import Foundation
import WebKit

/// État partagé entre la vue SwiftUI et le WKWebView.
final class WebModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    weak var webView: WKWebView?

    /// Recharge la page courante (ou la page d'accueil si rien n'est chargé).
    func reload() {
        errorMessage = nil
        guard let web = webView else { return }
        if web.url == nil {
            web.load(URLRequest(url: Config.siteURL))
        } else {
            web.reload()
        }
    }
}
