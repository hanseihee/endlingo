import SwiftUI

@main
struct endlingoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("notificationHour") private var notificationHour: Int = 9
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0

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
            .task {
                if hasCompletedOnboarding {
                    NotificationService.shared.scheduleDailyNotification(
                        hour: notificationHour, minute: notificationMinute
                    )
                }
            }
        }
    }
}
