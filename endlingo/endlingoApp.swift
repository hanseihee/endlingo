import SwiftUI
import FirebaseCore

@main
struct endlingoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("notificationHour") private var notificationHour: Int = 9
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0

    @State private var auth = AuthService.shared

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading {
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        Image("MainCharacter")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    }
                } else if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingContainerView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .onOpenURL { url in
                Task { await auth.handleDeepLink(url: url) }
            }
            .task(id: hasCompletedOnboarding) {
                guard hasCompletedOnboarding else { return }
                NotificationService.shared.scheduleDailyNotification(
                    hour: notificationHour, minute: notificationMinute
                )
            }
        }
    }
}
