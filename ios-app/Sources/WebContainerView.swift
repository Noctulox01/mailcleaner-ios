import SwiftUI

struct WebContainerView: View {
    @StateObject private var model = WebModel()

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            WebView(model: model)
                .ignoresSafeArea(.container, edges: .bottom)

            // Fine barre de progression en haut pendant le chargement
            if model.isLoading && model.progress < 1 {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .transition(.opacity)
            }

            // Écran d'erreur (pas de réseau, serveur injoignable…)
            if let err = model.errorMessage {
                ErrorView(message: err) { model.reload() }
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.isLoading)
        .animation(.default, value: model.errorMessage)
    }
}

private struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Connexion impossible")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Réessayer")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
