import SwiftUI

@main
struct MailCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            WebContainerView()
                .preferredColorScheme(nil) // suit le réglage clair/sombre du système
        }
    }
}
