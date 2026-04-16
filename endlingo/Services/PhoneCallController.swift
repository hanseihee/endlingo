@preconcurrency import AVFoundation
import CallKit
import Foundation
import SwiftUI

/// CallKit 래퍼. `CXProvider`/`CXCallController` 수명 주기와 `RealtimeVoiceService` 연결을 조율합니다.
///
/// 책임:
/// - `reportNewIncomingCall`로 시스템 수신 UI 트리거
/// - `CXProviderDelegate` 콜백 → RealtimeVoiceService 연결/해제
/// - AVAudioSession은 CallKit이 소유 (didActivate에서 audio engine 시작)
/// - 중국 지역 감지 시 CallKit 비활성화 (Apple China 정책)
@Observable
@MainActor
final class PhoneCallController: NSObject {
    static let shared = PhoneCallController()

    // MARK: - State

    enum Phase: Equatable {
        case idle
        case ringing         // reportNewIncomingCall 호출, 사용자 응답 대기 중
        case connecting      // 수락 후 ephemeral key 대기 + WebSocket 연결 중
        case active          // 통화 진행 중
        case ended(reason: String?)  // 정상 종료 또는 에러
    }

    private(set) var phase: Phase = .idle
    private(set) var currentScenario: PhoneCallScenario?
    /// 현재 통화에서 뽑힌 시나리오 variant (opening/situation/mood/persona name 등이 확정된 상태).
    /// UI/History/CallKit 표시는 모두 이 variant를 우선 사용.
    private(set) var currentVariant: ScenarioVariant?
    private(set) var callStartDate: Date?
    private(set) var callEndDate: Date?

    /// 중국 지역에서 실행 중인지 여부. CallKit은 iOS China SKU에서 차단됩니다.
    var isCallKitAvailable: Bool {
        // iOS 16+: Locale.Region
        if let region = Locale.current.region?.identifier {
            return region != "CN"
        }
        return true
    }

    // MARK: - CallKit Primitives

    @ObservationIgnored
    private lazy var provider: CXProvider = {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false
        let provider = CXProvider(configuration: config)
        provider.setDelegate(self, queue: nil)
        return provider
    }()

    @ObservationIgnored private let callController = CXCallController()
    @ObservationIgnored private var currentCallUUID: UUID?
    @ObservationIgnored private var ephemeralKeyTask: Task<RealtimeSessionAPI.EphemeralKeyResponse, Error>?
    @ObservationIgnored private var geminiSessionTask: Task<GeminiSessionAPI.SessionResponse, Error>?
    /// Edge Function이 pending row로 만들어둔 phone_call_sessions.id.
    /// 통화 종료 시 이 id로 UPDATE 해서 pending → completed로 전환.
    private(set) var currentSessionId: UUID?
    private var nativeLanguageCode: String {
        switch Locale.current.language.languageCode?.identifier {
        case "ja": return "Japanese"
        case "vi": return "Vietnamese"
        case "ko": return "Korean"
        default: return "English"
        }
    }
    @ObservationIgnored private var currentLevel: EnglishLevel = .a2
    /// 현재 통화의 최대 시간 (초). SubscriptionService.currentTier에서 결정.
    private(set) var maxDurationSeconds: Int = 60

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// 현재 통화에 사용 중인 AI provider.
    private(set) var currentProvider: CallAIProvider = .openAI

    /// 전화 오는 연출을 시작합니다. 사용자가 수락하면 자동으로 WebSocket 연결이 이어집니다.
    /// CallKit이 사용 불가한 지역에서는 즉시 `.ended(reason:)`로 종료됩니다 — 호출자가 fallback UI를 제공해야 합니다.
    func incomingCall(scenario: PhoneCallScenario, level: EnglishLevel, aiProvider: CallAIProvider = .openAI) {
        guard isCallKitAvailable else {
            phase = .ended(reason: String(localized: "이 지역에서는 AI 전화영어 기능을 사용할 수 없습니다"))
            return
        }
        // 이미 통화 중이면 무시
        if case .idle = phase {} else if case .ended = phase {} else { return }

        currentScenario = scenario
        currentProvider = aiProvider
        maxDurationSeconds = SubscriptionService.shared.currentTier.maxSingleCallSeconds
        // 매 통화마다 시나리오 variant를 새로 뽑아 대화를 다양화.
        let variant = scenario.randomVariant()
        currentVariant = variant
        print("[PhoneCall] variant — name=\(variant.personaName), situation=\(variant.situationLabel), params=\(variant.resolvedParameters)")
        currentLevel = level
        callStartDate = nil
        callEndDate = nil
        currentSessionId = nil

        let uuid = UUID()
        currentCallUUID = uuid

        // 서버 session_id + quota 미리 발급 (provider별 분기)
        if currentProvider == .openAI {
            ephemeralKeyTask = Task {
                try await RealtimeSessionAPI.fetchEphemeralKey(scenario: scenario, personaNameOverride: variant.personaName)
            }
        } else {
            geminiSessionTask = Task {
                try await GeminiSessionAPI.registerSession(scenario: scenario, personaNameOverride: variant.personaName)
            }
        }

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: variant.personaName)
        update.localizedCallerName = "\(scenario.emoji) \(variant.personaName) · AI"
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        phase = .ringing
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.phase = .ended(reason: error.localizedDescription)
                    self.cleanup()
                }
            }
        }
    }

    /// 사용자가 앱 UI에서 직접 "통화 종료" 버튼을 누를 때 호출합니다.
    /// CallKit delegate의 `CXEndCallAction`으로 이어지며 정리 로직도 거기서 실행됩니다.
    func endCurrentCall() {
        guard let uuid = currentCallUUID else { return }
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        callController.request(transaction) { error in
            if let error {
                print("CallKit end call failed: \(error.localizedDescription)")
            }
        }
    }

    /// 음소거 토글. CallKit transaction으로 처리해 시스템 음소거 상태와 동기화합니다.
    func setMuted(_ muted: Bool) {
        guard let uuid = currentCallUUID else { return }
        let action = CXSetMutedCallAction(call: uuid, muted: muted)
        let transaction = CXTransaction(action: action)
        callController.request(transaction) { _ in }
    }

    /// 통화 종료 후 다음 통화를 받기 위해 상태를 초기화합니다.
    /// `.ended` 상태에서만 실행하여 활성 통화를 끊지 않습니다.
    func resetToIdle() {
        guard case .ended = phase else { return }
        phase = .idle
        currentScenario = nil
        currentVariant = nil
        callStartDate = nil
        callEndDate = nil
        currentSessionId = nil
    }

    // MARK: - Private

    private func cleanup() {
        currentCallUUID = nil
        ephemeralKeyTask?.cancel()
        ephemeralKeyTask = nil
        geminiSessionTask?.cancel()
        geminiSessionTask = nil
        // 연결 실패 등으로 통화가 즉시 종료된 경우 pending row를 completed로 전환.
        // CallEndedView를 거치지 않는 경로에서 pending row가 남아 다음 통화를 차단하는 것을 방지.
        if let sessionId = currentSessionId {
            cancelPendingSession(sessionId: sessionId)
        }
        RealtimeVoiceService.shared.disconnect()
    }

    /// pending 상태인 session row를 duration=0으로 완료 처리.
    private func cancelPendingSession(sessionId: UUID) {
        Task {
            guard let token = await AuthService.shared.accessToken else { return }
            let payload: [String: Any] = [
                "status": "completed",
                "duration_seconds": 0,
                "completed_at": ISO8601DateFormatter().string(from: Date()),
            ]
            var request = URLRequest(url: URL(string: "\(SupabaseConfig.restBaseURL)/phone_call_sessions?id=eq.\(sessionId.uuidString)")!)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            _ = try? await URLSession.shared.data(for: request)
            print("[PhoneCall] pending session \(sessionId) → completed (cleanup)")
        }
    }

    /// 통화 지속 시간 (초). 진행 중/종료 후 모두 사용 가능.
    var elapsedSeconds: Int {
        guard let start = callStartDate else { return 0 }
        let end = callEndDate ?? Date()
        return max(0, Int(end.timeIntervalSince(start)))
    }
}

// MARK: - CXProviderDelegate

extension PhoneCallController: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            self.phase = .ended(reason: nil)
            self.callEndDate = Date()
            self.cleanup()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            guard let scenario = self.currentScenario else {
                action.fail()
                return
            }
            self.phase = .connecting
            self.callStartDate = Date()

            do {
                guard let variant = self.currentVariant else {
                    action.fail()
                    self.phase = .ended(reason: "variant missing")
                    return
                }

                var ephemeralKey = ""
                // OpenAI: ephemeral key 대기, Gemini: 건너뜀 (Firebase SDK가 인증 처리)
                if self.currentProvider == .openAI {
                    guard let task = self.ephemeralKeyTask else {
                        action.fail()
                        self.phase = .ended(reason: "session key task missing")
                        return
                    }
                    let keyResponse = try await task.value
                    self.currentSessionId = keyResponse.sessionId
                    if let serverMax = keyResponse.maxDurationSeconds, serverMax > 0 {
                        self.maxDurationSeconds = serverMax
                    }
                    ephemeralKey = keyResponse.ephemeralKey
                    print("[PhoneCall] ephemeral key received, model=\(keyResponse.model ?? "?"), tier=\(keyResponse.tier ?? "?"), maxDuration=\(self.maxDurationSeconds)s, session_id=\(keyResponse.sessionId?.uuidString ?? "nil")")
                } else {
                    print("[PhoneCall] Gemini path — waiting for gemini session task…")
                    guard let task = self.geminiSessionTask else {
                        print("[PhoneCall] ❌ geminiSessionTask is nil!")
                        action.fail()
                        self.phase = .ended(reason: "gemini session task missing")
                        return
                    }
                    do {
                        let sessionResponse = try await task.value
                        self.currentSessionId = sessionResponse.sessionId
                        if let serverMax = sessionResponse.maxDurationSeconds, serverMax > 0 {
                            self.maxDurationSeconds = serverMax
                        }
                        print("[PhoneCall] ✅ Gemini session registered, tier=\(sessionResponse.tier ?? "?"), maxDuration=\(self.maxDurationSeconds)s, session_id=\(sessionResponse.sessionId?.uuidString ?? "nil")")
                    } catch {
                        print("[PhoneCall] ❌ Gemini session FAILED: \(error)")
                        print("[PhoneCall] error type: \(type(of: error)), desc: \(error.localizedDescription)")
                        // quota 실패해도 통화 시도는 계속 (Firebase SDK가 직접 연결)
                        print("[PhoneCall] continuing without server session…")
                    }
                }

                await RealtimeVoiceService.shared.connect(
                    scenario: scenario,
                    variant: variant,
                    level: self.currentLevel,
                    nativeLanguage: self.nativeLanguageCode,
                    ephemeralKey: ephemeralKey,
                    provider: self.currentProvider
                )
                print("[PhoneCall] after connect, voice state=\(RealtimeVoiceService.shared.state)")

                // 연결 성공/실패 확인
                switch RealtimeVoiceService.shared.state {
                case .connected:
                    self.phase = .active
                    action.fulfill()
                case .error(let msg):
                    action.fail()
                    self.phase = .ended(reason: msg)
                    self.endCurrentCall()
                default:
                    action.fulfill()
                    self.phase = .active
                }
            } catch {
                print("[PhoneCall] answerCall failed: \(error.localizedDescription)")
                action.fail()
                self.phase = .ended(reason: error.localizedDescription)
                self.endCurrentCall()
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            self.callEndDate = Date()
            self.phase = .ended(reason: nil)
            self.cleanup()
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            RealtimeVoiceService.shared.isMuted = action.isMuted
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // 시스템이 audio session 활성화 완료. .playAndRecord + voiceChat 모드 자동 설정됨.
        Task { @MainActor in
            RealtimeVoiceService.shared.startAudioEngine()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in
            RealtimeVoiceService.shared.stopAudioEngine()
        }
    }
}
