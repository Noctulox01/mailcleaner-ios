import SwiftUI

@main
struct MailCleanerApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.jobs)
                .tint(Brand.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            switch app.phase {
            case .launching:
                LaunchView()
            case .loggedOut:
                AuthView().transition(.opacity)
            case .mfa(let challenge):
                MFALoginView(challenge: challenge).transition(.move(edge: .trailing))
            case .loggedIn:
                MainTabView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.phase)
        .overlay(alignment: .top) { ToastOverlay() }
        .task { await app.boot() }
    }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 84)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }
            CleanView()
                .tabItem { Label("Nettoyer", systemImage: "sparkles") }
            RulesView()
                .tabItem { Label("Règles", systemImage: "line.3.horizontal.decrease.circle.fill") }
            ActivityView()
                .tabItem { Label("Activité", systemImage: "clock.fill") }
            AccountView()
                .tabItem { Label("Compte", systemImage: "person.crop.circle.fill") }
        }
    }
}
