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
            case .free: return 120      // 2분
            case .premium: return 600   // 10분
            }
        }

        /// 1회 통화 최대 시간 (초).
        var maxSingleCallSeconds: Int {
            switch self {
            case .free: return 120      // 2분
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

    /// Free → Premium 전환 시점 (UTC). Premium 상태가 아니면 nil.
    /// `PhoneCallHistoryService.todayUsedSeconds`에서 이 시점 이후 세션만 합산해
    /// "전환 후 깨끗한 quota 재시작" 정책을 구현한다.
    /// 서버와 완벽히 동일한 타임스탬프는 아니지만 UX 근사치로 충분.
    private(set) var premiumActivatedAt: Date?

    /// Premium 여부 편의 프로퍼티.
    var isPremium: Bool { currentTier == .premium }

    @ObservationIgnored
    private var customerInfoTask: Task<Void, Never>?

    /// F4: 마지막 purchase/restore 시각. RC 서버가 영수증을 반영하기 전 짧은 시차에
    /// sync-subscription이 free를 돌려주더라도 이 grace window 동안은 premium을 유지해
    /// "구매 직후 Free UI로 튀는" 현상을 막는다. 또한 서버가 명시적으로 "pending"을
    /// 돌려주는 경우에도 본 local tier를 덮어쓰지 않는다.
    @ObservationIgnored
    private var optimisticPremiumUntil: Date?
    private static let purchaseGraceWindow: TimeInterval = 15

    // MARK: - Configuration

    private static let apiKey = "appl_dZdecswLYrPEMecCiffexKcQPHo"
    private static let entitlementId = "premium"

    private init() {}

    /// 앱 시작 시 1회 호출. RevenueCat SDK 초기화 + customerInfo 스트림 구독.
    ///
    /// F2 fix: configure 자체는 즉시 수행해 다른 곳에서 `Purchases.shared`를 호출해도
    /// crash가 나지 않게 하고, 그 직후 auth 세션 복원을 기다려 가능한 한 빨리
    /// identified user로 logIn한다. `.onChange(of: auth.isLoggedIn)` 경로와 race가
    /// 나도 `Purchases.logIn`은 멱등이라 안전.
    func configure() async {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        startCustomerInfoListener()

        // auth.isLoading이 true인 동안 세션 복원 진행 중. 최대 3초 대기.
        await waitForAuthRestore(maxSeconds: 3)

        if let userId = AuthService.shared.userId?.uuidString.lowercased() {
            print("[Subscription] configure → logIn identified userId=\(userId)")
            await logIn(userId: userId)
        } else {
            print("[Subscription] configure anonymously (no auth session yet)")
            await refreshTier()
        }
    }

    /// AuthService.isLoading이 false가 될 때까지 대기 (50ms polling, 최대 maxSeconds).
    /// 세션 복원이 오래 걸리거나 실패해도 configure가 무한 대기하지 않도록 timeout.
    private func waitForAuthRestore(maxSeconds: Double) async {
        let start = Date()
        while AuthService.shared.isLoading {
            if Date().timeIntervalSince(start) >= maxSeconds { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - Auth Integration

    /// AuthService 로그인 직후 호출. RevenueCat에 userId를 연결해
    /// 디바이스 간 구독 상태를 동기화합니다.
    /// UUID는 lowercase로 normalize — RC/Supabase 양쪽 일관성 유지.
    ///
    /// `Purchases.logIn` 응답의 customerInfo는 cached 값이라 entitlement가 stale일 수
    /// 있다(특히 alias 처리·구매 직후). 그 stale 값으로 syncToServer를 호출하면 서버가
    /// 정직하게 free로 응답해 잘못된 강등이 발생하므로, 명시적으로 fresh fetch로
    /// 한 번 더 받아 정확한 상태를 sync한다.
    func logIn(userId: String) async {
        let normalized = userId.lowercased()
        do {
            _ = try await Purchases.shared.logIn(normalized)
            let info = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            updateTier(from: info)
            await syncToServer(customerInfo: info)
            print("[Subscription] logIn userId=\(normalized), tier=\(currentTier.rawValue)")
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
        // F4: purchase 성공 = Apple 영수증 유효. RC 서버가 아직 처리 전이어도 premium 보장.
        optimisticPremiumUntil = Date().addingTimeInterval(Self.purchaseGraceWindow)
        // 구매 직후 서버 `user_subscriptions`에 즉시 반영.
        await syncToServer(customerInfo: customerInfo)
        return !userCancelled
    }

    /// 구매 복원. Apple 리뷰 시 "복원 구매" 버튼 필수.
    func restore() async throws {
        isLoading = true
        defer { isLoading = false }

        let customerInfo = try await Purchases.shared.restorePurchases()
        updateTier(from: customerInfo)
        // F4: restore 직후에도 Apple 영수증은 유효 — RC 서버 지연 중 free downgrade 보류.
        optimisticPremiumUntil = Date().addingTimeInterval(Self.purchaseGraceWindow)
        await syncToServer(customerInfo: customerInfo)
    }

    // MARK: - Private

    /// 서버에서 최신 customerInfo를 가져와 tier 갱신.
    /// fetchPolicy를 명시해 SDK 캐시 대신 RC 서버의 최신 entitlement를 받는다.
    func refreshTier() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            updateTier(from: customerInfo)
            // 로그인된 경우 서버 user_subscriptions도 함께 최신화 (webhook 지연 보정).
            if AuthService.shared.isLoggedIn {
                await syncToServer(customerInfo: customerInfo)
            }
        } catch {
            print("[Subscription] refreshTier failed: \(error.localizedDescription)")
        }
    }

    /// `sync-subscription` Edge Function으로 서버에 구독 상태 동기화 요청.
    /// 서버는 클라 body를 무시하고 RevenueCat REST API로 직접 재검증하므로,
    /// 여기서 보내는 payload는 진단·로깅용 hint일 뿐 신뢰 근거가 아니다.
    private func syncToServer(customerInfo: CustomerInfo) async {
        guard AuthService.shared.isLoggedIn,
              let token = await AuthService.shared.accessToken else { return }

        let entitlement = customerInfo.entitlements[Self.entitlementId]
        let isPremium = entitlement?.isActive == true

        // 서버가 RevenueCat API로 재검증하므로 body는 최소화 (진단용 hint).
        let payload: [String: Any] = ["is_premium": isPremium]

        guard let url = URL(string: "\(SupabaseConfig.functionsBaseURL)/sync-subscription") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Subscription] sync-subscription status=\(status), isPremium=\(isPremium)")

            // 서버 응답에서 tier/premium_activated_at을 받아 로컬 상태를 서버 truth로 재동기화.
            // RevenueCat SDK의 customerInfo는 캐시 기반이라 구독 만료 직후에도 isActive=true가
            // 잠깐 유지될 수 있는데, 서버는 REST API로 실시간 조회하므로 더 정확하다.
            if (200..<300).contains(status),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // F3 응답: 서버가 RC REST 조회로 subscriber를 확정 못 한 경우(신규 생성된
                // 빈 subscriber 등)를 "pending"으로 내려준다. 이때는 local tier를 건드리지 않고
                // 다음 sync(scenePhase 복귀, customerInfoStream, 재구매 등)를 기다린다.
                if let verification = json["verification"] as? String, verification == "pending" {
                    print("[Subscription] sync-subscription verification pending — keeping local tier=\(currentTier.rawValue)")
                    return
                }

                if let serverTierStr = json["tier"] as? String {
                    let serverTier: Tier = serverTierStr == "premium" ? .premium : .free

                    // F4: purchase/restore 직후 grace window 동안은 premium → free 강등 보류.
                    // Apple 영수증이 유효하지만 RC 서버가 아직 처리 못 했을 가능성이 크다.
                    let withinGrace = optimisticPremiumUntil.map { Date() < $0 } ?? false
                    let wouldDowngrade = currentTier == .premium && serverTier == .free

                    if serverTier != currentTier {
                        if wouldDowngrade && withinGrace {
                            print("[Subscription] server=free within purchase grace — holding premium")
                        } else {
                            print("[Subscription] tier corrected by server: \(currentTier.rawValue) → \(serverTier.rawValue)")
                            currentTier = serverTier
                            if serverTier == .free {
                                premiumActivatedAt = nil
                            }
                        }
                    }
                }
                if let iso = json["premium_activated_at"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
                        premiumActivatedAt = date
                    }
                } else if json["premium_activated_at"] is NSNull {
                    // 서버가 free로 내렸지만 로컬이 grace window로 premium 유지 중이면
                    // premiumActivatedAt을 nil로 바꾸면 quota 계산이 어긋나므로 덮어쓰지 않음.
                    if currentTier == .free {
                        premiumActivatedAt = nil
                    }
                }
            }
        } catch {
            print("[Subscription] sync-subscription failed: \(error.localizedDescription)")
        }
    }

    private func updateTier(from customerInfo: CustomerInfo) {
        let wasActive = currentTier == .premium
        let entitlement = customerInfo.entitlements[Self.entitlementId]
        let isActive = entitlement?.isActive == true

        // 디버그: entitlement 상태 상세 출력
        print("[Subscription] entitlements keys: \(Array(customerInfo.entitlements.all.keys))")
        print("[Subscription] '\(Self.entitlementId)' → isActive=\(isActive), productId=\(entitlement?.productIdentifier ?? "nil")")

        if isActive {
            currentTier = .premium
            // 앱 재실행 직후에도 wasActive=false이므로 무조건 Date()로 찍으면
            // quota 계산이 매번 리셋된다. premiumActivatedAt이 nil일 때만 임시 세팅하고,
            // 서버 동기화(syncToServer) 응답에서 서버 확정 시각으로 덮어쓴다.
            if !wasActive && premiumActivatedAt == nil {
                premiumActivatedAt = Date()
                print("[Subscription] premiumActivatedAt set (tentative) = \(premiumActivatedAt!)")
            }
        } else {
            currentTier = .free
            premiumActivatedAt = nil
        }
        if wasActive != isPremium {
            print("[Subscription] tier changed → \(currentTier.rawValue)")
        }
    }

    /// customerInfo 변경 실시간 감지 (구독 갱신, 만료, 환불, 가족 공유 등).
    /// @MainActor 클래스이므로 Task 내 직접 호출 가능.
    ///
    /// tier가 실제로 변경될 때마다 서버에도 동기화해 RevenueCat 캐시와 서버 측
    /// 실시간 판정 사이의 mismatch가 유지되지 않도록 한다. 샌드박스 자동 갱신이나
    /// logIn 직후 customerInfo 재발행처럼 비동기로 들어오는 이벤트도 서버에 반영됨.
    private func startCustomerInfoListener() {
        customerInfoTask?.cancel()
        customerInfoTask = Task { @MainActor [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                guard let self else { continue }
                let previousTier = self.currentTier
                self.updateTier(from: customerInfo)
                if self.currentTier != previousTier, AuthService.shared.isLoggedIn {
                    await self.syncToServer(customerInfo: customerInfo)
                }
            }
        }
    }
}
