import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import GoogleSignIn

@main
struct endlingoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("notificationHour") private var notificationHour: Int = 9
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0

    @State private var auth = AuthService.shared

    init() {
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        // GoogleSignIn SDK에 iOS Client ID 설정
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "65805250161-0ckmm3qdli8pkj7h5sge7jplvi9dfvqg.apps.googleusercontent.com"
        )
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
                // 위젯 딥링크는 Auth 핸들러로 보내지 않음
                guard url.host != "lesson" else { return }
                // Google Sign In URL 처리
                if auth.handleGoogleSignInURL(url) { return }
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
