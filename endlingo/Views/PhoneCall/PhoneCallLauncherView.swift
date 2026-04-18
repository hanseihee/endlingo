import SwiftUI

/// AI 전화영어 진입점. 시나리오를 고른 뒤 탭하면 CallKit 수신 UI가 뜹니다.
/// `PhoneCallController.phase`를 관찰해 통화 중(`active`)에는 `InCallView`,
/// 종료 직후(`ended`)에는 `CallEndedView`로 자동 전환합니다.
struct PhoneCallLauncherView: View {
    @AppStorage("selectedLevel") private var selectedLevelRaw: String = EnglishLevel.a2.rawValue

    private let controller = PhoneCallController.shared
    @State private var auth = AuthService.shared
    @State private var history = PhoneCallHistoryService.shared
    @State private var subscription = SubscriptionService.shared
    @State private var showPaywall = false
    @Environment(\.scenePhase) private var scenePhase

    private var level: EnglishLevel {
        EnglishLevel(rawValue: selectedLevelRaw) ?? .a2
    }

    private var isLimitReached: Bool { history.isLimitReached }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isLoggedIn {
                    loginRequiredView
                } else {
                    switch controller.phase {
                    case .idle, .ringing:
                        scenarioList
                    case .connecting, .active:
                        InCallView()
                    case .ended:
                        CallEndedView(onDismiss: {
                            // 탭 전용이므로 sheet dismiss 대신 상태만 리셋해 scenarioList로 복귀
                            controller.resetToIdle()
                        })
                    }
                }
            }
            .navigationTitle("AI 전화영어")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if auth.isLoggedIn, case .idle = controller.phase {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            PhoneCallHistoryView()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                }
            }
        }
        .onAppear {
            // 사용자가 이전 통화의 CallEndedView를 "완료"로 닫지 않고
            // 스와이프 dismiss한 경우를 대비한 안전망
            if case .ended = controller.phase {
                controller.resetToIdle()
            }
        }
        .task {
            print("[Launcher] onTask — loggedIn=\(auth.isLoggedIn), userId=\(auth.userId?.uuidString ?? "nil"), today=\(history.todayCallCount), remaining=\(history.remainingTodayCallCount)")
            await history.refreshFromServer()
            print("[Launcher] after refresh — today=\(history.todayCallCount), remaining=\(history.remainingTodayCallCount), isLimitReached=\(isLimitReached)")
        }
        // 앱이 background에서 foreground로 복귀할 때 quota/구독 상태를 다시 당겨온다.
        // 다른 기기 사용, webhook 반영, 이전 PATCH 실패분을 자동 반영.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, auth.isLoggedIn else { return }
            Task {
                await history.refreshFromServer()
                await subscription.refreshTier()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Login Required

    private var loginRequiredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .padding(.top, 40)

            Text("로그인이 필요해요")
                .font(.title3.bold())

            Text("AI 전화영어는 로그인한 사용자만 이용할 수 있어요. 사용자별 일일 이용 횟수를 관리하기 위함입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Text("프로필 탭에서 로그인하세요")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var isInCall: Bool {
        switch controller.phase {
        case .idle: return false
        case .ended: return false
        default: return true
        }
    }

    // MARK: - Scenario List

    private var scenarioList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introCard

                // 차단성 알림(지역 제한/한도 초과)은 시나리오 탭 전에 인지할 수 있도록 상단에 배치
                blockingNotice

                VStack(alignment: .leading, spacing: 8) {
                    Text("시나리오를 선택하세요")
                        .font(.headline)
                        .padding(.horizontal, 16)

                    LazyVStack(spacing: 10) {
                        ForEach(PhoneCallScenario.allCases) { scenario in
                            scenarioRow(scenario)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // 기본 이용 안내는 부가정보이므로 하단 유지
                tipNotice
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "phone.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                Text("베타")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Capsule())
            }
            Text("실제 전화처럼 AI와 영어로 통화해보세요")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("시나리오를 선택하면 AI가 먼저 전화를 걸어옵니다")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 6) {
                Text("현재 레벨")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text(level.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Capsule())

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "phone.arrow.up.right.fill")
                        .font(.caption2)
                    let remainMin = history.remainingTodaySeconds / 60
                    let remainSec = history.remainingTodaySeconds % 60
                    Text("남은 시간 \(remainMin):\(String(format: "%02d", remainSec))")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    isLimitReached
                        ? Color.red.opacity(0.35)
                        : Color.white.opacity(0.22)
                )
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func scenarioRow(_ scenario: PhoneCallScenario) -> some View {
        Button {
            guard !isLimitReached else { return }
            controller.incomingCall(scenario: scenario, level: level)
        } label: {
            HStack(spacing: 12) {
                Image(scenario.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .frame(width: 56, height: 56)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(scenario.title))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(LocalizedStringKey(scenario.description))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Image(systemName: "person.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(scenario.personaName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(LocalizedStringKey(scenario.personaRole))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                Spacer()

                Image(systemName: "phone.fill")
                    .foregroundStyle(.white)
                    .font(.callout.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.green)
                    .clipShape(Circle())
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(isLimitReached ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isLimitReached)
    }

    /// 시나리오 진행을 차단하는 상태 알림(지역 제한, 일일 한도 초과).
    /// 사용자가 시나리오를 탭해보기 전에 인지할 수 있게 introCard 바로 아래에 노출.
    @ViewBuilder
    private var blockingNotice: some View {
        if !controller.isCallKitAvailable {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("사용 불가 지역")
                        .font(.footnote.bold())
                }
                .foregroundStyle(.orange)
                Text("현재 지역에서는 전화 기능을 사용할 수 없습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        } else if isLimitReached {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "hourglass")
                    Text("오늘 통화를 모두 사용했어요")
                        .font(.footnote.bold())
                }
                .foregroundStyle(.red)

                if !subscription.isPremium {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.yellow)
                            Text("Premium으로 업그레이드 (하루 10분)")
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Text("내일 다시 시도해주세요. 매일 자정(UTC)에 초기화됩니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    /// 기본 이용 안내(차단 상태가 아닐 때만 표시).
    @ViewBuilder
    private var tipNotice: some View {
        if controller.isCallKitAvailable && !isLimitReached {
            VStack(alignment: .leading, spacing: 6) {
                Label("이용 안내", systemImage: "info.circle")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                Text("통화는 Google Gemini Live API로 연결됩니다. 조용한 환경에서 이어폰 사용을 권장합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    PhoneCallLauncherView()
}
