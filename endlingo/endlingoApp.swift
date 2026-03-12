import SwiftUI

@main
struct endlingoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading {
                    ProgressView()
                } else if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingContainerView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .onOpenURL { url in
                Task { await auth.handleDeepLink(url: url) }
            }
        }
    }
}
