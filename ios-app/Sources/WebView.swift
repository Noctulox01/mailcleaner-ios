import SwiftUI
import UIKit
import WebKit

/// Enveloppe SwiftUI autour d'un WKWebView qui affiche le site MailCleaner.
struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.websiteDataStore = .default() // garde les cookies/session entre les lancements
        cfg.applicationNameForUserAgent = "MailCleaneriOS" // ajouté à l'User-Agent Safari standard

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.keyboardDismissMode = .interactive

        // Barre de progression
        context.coordinator.progressObs = web.observe(\.estimatedProgress, options: .new) { [weak model] w, _ in
            DispatchQueue.main.async { model?.progress = w.estimatedProgress }
        }

        // Tirer pour rafraîchir
        let rc = UIRefreshControl()
        rc.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
        web.scrollView.refreshControl = rc

        model.webView = web
        web.load(URLRequest(url: Config.siteURL))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: WebModel
        var progressObs: NSKeyValueObservation?

        init(model: WebModel) { self.model = model }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            model.webView?.reload()
        }

        private func endRefresh(_ webView: WKWebView) {
            webView.scrollView.refreshControl?.endRefreshing()
        }

        // Démarrage
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.model.isLoading = true
                self.model.errorMessage = nil
            }
        }

        // Fin OK
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.model.isLoading = false
                self.endRefresh(webView)
            }
        }

        // Échecs
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error, webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error, webView)
        }

        private func report(_ error: Error, _ webView: WKWebView) {
            let ns = error as NSError
            // -999 = navigation annulée (ex. redirection) : on ignore.
            if ns.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async {
                self.model.isLoading = false
                self.endRefresh(webView)
                self.model.errorMessage = ns.localizedDescription
            }
        }

        // Liens externes -> Safari ; même domaine -> dans l'app.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
            let scheme = url.scheme?.lowercased() ?? ""

            // mailto:, tel:, etc. -> système
            if scheme != "http" && scheme != "https" {
                openExternally(url)
                return decisionHandler(.cancel)
            }

            // Lien cliqué vers un autre domaine -> Safari
            if navigationAction.navigationType == .linkActivated,
               let host = url.host, !host.hasSuffix(Config.internalHost) {
                openExternally(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        // target="_blank" / window.open : on charge dans la même vue au lieu de perdre le lien.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if let host = url.host, host.hasSuffix(Config.internalHost) {
                    webView.load(navigationAction.request)
                } else {
                    openExternally(url)
                }
            }
            return nil
        }

        private func openExternally(_ url: URL) {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
    }
}
