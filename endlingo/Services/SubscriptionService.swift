import Foundation
import RevenueCat
import SwiftUI

/// RevenueCat 구독 상태 관리 서비스.
///
/// 책임:
/// - RevenueCat SDK 초기화 (`configure`)
/// - 구독 상태(`currentTier`) 관찰 및 갱신
/// - AuthService 로그인/로그아웃 시 RevenueCat userId 연결/해제
/// - 구매/복원 처리 + offerings 로드
///
/// `endlingoApp`에서 `configure()` 1회 호출, `onChange(of: auth.isLoggedIn)`으로 자동 logIn/logOut 연동.
@Observable
@MainActor
final class SubscriptionService {
    static let shared = SubscriptionService()

    // MARK: - Types

    enum Tier: String, Sendable {
        case free
        case premium

        /// 하루 총 통화 가능 시간 (초). 여러 통화 합산.
        var dailyCallDurationSeconds: Int {
            switch self {
            case .free: return 60       // 1분
            case .premium: return 600   // 10분
            }
        }

        /// 1회 통화 최대 시간 (초).
        var maxSingleCallSeconds: Int {
            switch self {
            case .free: return 60       // 1분
            case .premium: return 600   // 10분
            }
        }

        /// 광고 표시 여부.
        var showAds: Bool {
            self == .free
        }
    }

    // MARK: - State

    private(set) var currentTier: Tier = .free
    private(set) var isLoading: Bool = false

    /// Premium 여부 편의 프로퍼티.
    var isPremium: Bool { currentTier == .premium }

    @ObservationIgnored
    private var customerInfoTask: Task<Void, Never>?

    // MARK: - Configuration

    private static let apiKey = "appl_dZdecswLYrPEMecCiffexKcQPHo"
    private static let entitlementId = "premium"

    private init() {}

    /// 앱 시작 시 1회 호출. RevenueCat SDK 초기화 + customerInfo 스트림 구독.
    func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        startCustomerInfoListener()

        Task {
            await refreshTier()
        }
        print("[Subscription] configured (apiKey=\(Self.apiKey.prefix(12))...)")
    }

    // MARK: - Auth Integration

    /// AuthService 로그인 직후 호출. RevenueCat에 userId를 연결해
    /// 디바이스 간 구독 상태를 동기화합니다.
    func logIn(userId: String) async {
        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            updateTier(from: customerInfo)
            print("[Subscription] logIn userId=\(userId), tier=\(currentTier.rawValue)")
        } catch {
            print("[Subscription] logIn failed: \(error.localizedDescription)")
        }
    }

    /// AuthService 로그아웃 시 호출. RevenueCat anonymous user로 복귀.
    func logOut() async {
        do {
            let customerInfo = try await Purchases.shared.logOut()
            updateTier(from: customerInfo)
            print("[Subscription] logOut, tier=\(currentTier.rawValue)")
        } catch {
            print("[Subscription] logOut failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Offerings

    /// PaywallView에서 호출. 현재 offering(월간/연간 패키지)을 로드합니다.
    func loadCurrentOffering() async throws -> Offering? {
        let offerings = try await Purchases.shared.offerings()
        return offerings.current
    }

    // MARK: - Purchase

    /// 패키지 구매 (월간 또는 연간). 구매 성공 시 tier 자동 업데이트.
    /// 반환값: true=구매 완료, false=사용자 취소.
    @discardableResult
    func purchase(package: Package) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)
        updateTier(from: customerInfo)
        return !userCancelled
    }

    /// 구매 복원. Apple 리뷰 시 "복원 구매" 버튼 필수.
    func restore() async throws {
        isLoading = true
        defer { isLoading = false }

        let customerInfo = try await Purchases.shared.restorePurchases()
        updateTier(from: customerInfo)
    }

    // MARK: - Private

    /// 서버에서 최신 customerInfo를 가져와 tier 갱신.
    func refreshTier() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateTier(from: customerInfo)
        } catch {
            print("[Subscription] refreshTier failed: \(error.localizedDescription)")
        }
    }

    private func updateTier(from customerInfo: CustomerInfo) {
        let wasActive = currentTier == .premium
        if customerInfo.entitlements[Self.entitlementId]?.isActive == true {
            currentTier = .premium
        } else {
            currentTier = .free
        }
        if wasActive != isPremium {
            print("[Subscription] tier changed → \(currentTier.rawValue)")
        }
    }

    /// customerInfo 변경 실시간 감지 (구독 갱신, 만료, 환불, 가족 공유 등).
    private func startCustomerInfoListener() {
        customerInfoTask?.cancel()
        customerInfoTask = Task { [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                await MainActor.run { [weak self] in
                    self?.updateTier(from: customerInfo)
                }
            }
        }
    }
}
