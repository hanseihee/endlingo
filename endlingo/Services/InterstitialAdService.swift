import Foundation
import GoogleMobileAds
import UIKit

/// AdMob 전체화면(interstitial) 광고 관리.
///
/// 책임:
/// - 앱 시작 시 광고 사전 로드 (`preload`)
/// - 전화영어 탭 진입 시 광고 표시 (`showIfReady`)
/// - Premium 사용자는 자동 skip
/// - cooldown으로 과도한 노출 방지 (UX 보호)
/// - 표시 후 다음 광고 자동 사전 로드
@Observable
@MainActor
final class InterstitialAdService: NSObject {
    static let shared = InterstitialAdService()

    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var lastShownAt: Date?
    @ObservationIgnored private var isLoading: Bool = false

    /// 같은 광고가 너무 자주 노출되는 것을 방지하는 cooldown.
    /// 사용자가 전화영어 탭을 짧은 시간 안에 여러 번 들락거려도 한 번만 표시.
    private static let cooldownSeconds: TimeInterval = 180  // 3분

    // AdMob 광고 단위 ID. Debug는 Google 공식 테스트 ID로 항상 정상 광고 송출,
    // Release는 AdMob Console에서 발급한 endlingo 전용 interstitial 단위.
    #if DEBUG
    private static let adUnitId = "ca-app-pub-3940256099942544/4411468910"
    #else
    private static let adUnitId = "ca-app-pub-4582716621646848/1432634226"
    #endif

    private override init() {
        super.init()
    }

    /// 앱 시작 시 1회 호출. 다음 표시를 위해 미리 로드해둔다.
    func preload() {
        Task { @MainActor in
            await loadAd()
        }
    }

    /// 전화영어 탭 진입 시 호출.
    /// Premium 사용자나 cooldown 중에는 호출되어도 표시되지 않음.
    func showIfReady() {
        guard !SubscriptionService.shared.isPremium else {
            print("[InterstitialAd] Premium 유저 — skip")
            return
        }
        if let last = lastShownAt, Date().timeIntervalSince(last) < Self.cooldownSeconds {
            print("[InterstitialAd] cooldown 중 — skip")
            return
        }
        guard let ad = interstitial else {
            print("[InterstitialAd] 로드 안 됨 — 광고 skip하고 사전 로드 재시도")
            Task { await loadAd() }
            return
        }
        guard let rootVC = currentRootViewController() else {
            print("[InterstitialAd] rootViewController 못 찾음")
            return
        }
        ad.present(from: rootVC)
        lastShownAt = Date()
        // present 후 ad 인스턴스는 1회용 — 다음 광고는 dismiss 시 재로드.
        interstitial = nil
    }

    // MARK: - Private

    private func loadAd() async {
        guard !isLoading else { return }
        guard interstitial == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let ad = try await InterstitialAd.load(with: Self.adUnitId, request: Request())
            ad.fullScreenContentDelegate = self
            interstitial = ad
            print("[InterstitialAd] 로드 완료")
        } catch {
            print("[InterstitialAd] 로드 실패: \(error.localizedDescription)")
        }
    }

    private func currentRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - FullScreenContentDelegate

extension InterstitialAdService: FullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor [weak self] in
            print("[InterstitialAd] dismissed — 다음 광고 사전 로드")
            await self?.loadAd()
        }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor [weak self] in
            print("[InterstitialAd] present 실패: \(error.localizedDescription)")
            self?.interstitial = nil
            await self?.loadAd()
        }
    }
}
