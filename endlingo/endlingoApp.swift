import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import GoogleSignIn
import GoogleMobileAds
import RevenueCat

@main
struct endlingoApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("notificationHour") private var notificationHour: Int = 9
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0

    @State private var auth = AuthService.shared
    @State private var updateService = AppUpdateService.shared

    init() {
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        // GoogleSignIn SDK에 iOS Client ID 설정
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "65805250161-0ckmm3qdli8pkj7h5sge7jplvi9dfvqg.apps.googleusercontent.com"
        )
        // Google Mobile Ads 초기화
        MobileAds.shared.start(completionHandler: nil)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if updateService.shouldForceUpdate {
                    ForceUpdateView(
                        message: updateService.updateMessage,
                        appStoreURL: updateService.appStoreURL
                    )
                } else if auth.isLoading {
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
            .task {
                // RevenueCat SDK 초기화 (auth 세션 복원 후 identified user로 시작).
                await SubscriptionService.shared.configure()
                // AdMob interstitial 광고 사전 로드 (전화영어 탭 진입 시 노출).
                InterstitialAdService.shared.preload()
                await updateService.checkForUpdate()
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
            // RevenueCat userId 연동 — AuthService 상태 변화 시 자동 logIn/logOut
            .onChange(of: auth.isLoggedIn) { _, isLoggedIn in
                Task {
                    if isLoggedIn, let userId = auth.userId?.uuidString {
                        await SubscriptionService.shared.logIn(userId: userId)
                    } else {
                        await SubscriptionService.shared.logOut()
                    }
                }
            }
        }
    }
}
