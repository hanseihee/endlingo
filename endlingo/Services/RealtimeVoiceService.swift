@preconcurrency import AVFoundation
import Foundation
import SwiftUI

/// AI 실시간 음성 통화 파사드.
///
/// UI(InCallView)와 PhoneCallController가 직접 참조하는 유일한 서비스.
/// 실제 네트워크 전송은 `GeminiLiveAdapter`에 위임하고,
/// 오디오 캡처/재생은 `CallAudioPipeline`에 위임합니다.
@Observable
@MainActor
final class RealtimeVoiceService: NSObject {
    static let shared = RealtimeVoiceService()

    // MARK: - State (공개 — UI/Controller가 관찰)

    enum State: Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case error(String)
    }

    enum Speaker { case user, assistant }

    struct TranscriptEntry: Identifiable, Hashable {
        let id = UUID()
        let speaker: Speaker
        var text: String
        var translation: String?
        let createdAt: Date
    }

    private(set) var state: State = .idle
    private(set) var isAssistantSpeaking: Bool = false
    private(set) var transcript: [TranscriptEntry] = []
    private(set) var partialUserText: String = ""
    private(set) var partialAssistantText: String = ""
    var isMuted: Bool = false {
        didSet { audioPipeline?.isMuted = isMuted }
    }
    private(set) var isSpeakerOn: Bool = true

    // MARK: - Provider & Pipeline

    @ObservationIgnored private var adapter: RealtimeProviderAdapter?
    @ObservationIgnored private var audioPipeline: CallAudioPipeline?

    // MARK: - Transcript Helpers

    @ObservationIgnored private var pendingUserEntryId: UUID?
    @ObservationIgnored private var userTranscriptDeltaCount: Int = 0

    // MARK: - Diagnostic counters (기존 호환)
    @ObservationIgnored private var speechStartedCount: Int = 0
    @ObservationIgnored private var speechStoppedCount: Int = 0
    @ObservationIgnored private var audioCommittedCount: Int = 0
    @ObservationIgnored private var echoDropCount: Int = 0

    // MARK: - Lifecycle

    private override init() {
        super.init()
    }

    // MARK: - Public API (기존과 동일한 시그니처)

    /// Gemini Live API에 연결하고 세션을 구성합니다.
    /// - 선행 조건: AVAudioSession이 이미 활성화돼 있어야 함 (CallKit이 처리).
    func connect(
        scenario: PhoneCallScenario,
        variant: ScenarioVariant,
        level: EnglishLevel,
        nativeLanguage: String
    ) async {
        guard state != .connecting && state != .connected else { return }
        state = .connecting
        resetState()

        let selectedAdapter: RealtimeProviderAdapter = GeminiLiveAdapter()
        adapter = selectedAdapter

        let pipeline = CallAudioPipeline(
            inputSampleRate: selectedAdapter.inputSampleRate,
            outputSampleRate: selectedAdapter.outputSampleRate
        )
        pipeline.onAllPlaybackFinished = { [weak self] in
            self?.handleAllPlaybackFinished()
        }
        // Bug fix: 오디오 엔진 실패 시 .error state 전파
        pipeline.onStartFailed = { [weak self] message in
            self?.state = .error(message)
        }
        // Bug fix: 이전 통화에서 남은 mute/speaker 상태를 새 pipeline에 동기화
        pipeline.isMuted = isMuted
        pipeline.setSpeakerEnabled(isSpeakerOn)
        audioPipeline = pipeline

        // 진단: 현재 마이크 권한 + AVAudioSession 상태 덤프
        let audioSession = AVAudioSession.sharedInstance()
        let permission: String
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permission = "granted"
        case .denied: permission = "denied"
        case .undetermined: permission = "undetermined"
        @unknown default: permission = "unknown"
        }
        print("[RealtimeVoice] connect start — micPermission=\(permission), inputAvail=\(audioSession.isInputAvailable), category=\(audioSession.category.rawValue)")

        let config = ProviderSessionConfig(
            instructions: scenario.instructions(for: level, nativeLanguage: nativeLanguage, variant: variant),
            voice: variant.voice,
            firstResponseInstructions: variant.firstResponseInstructions,
            geminiModel: "gemini-3.1-flash-live-preview"
        )

        do {
            print("[RealtimeVoice] calling adapter.connect")
            try await selectedAdapter.connect(config: config, delegate: self)
            if state == .connecting { state = .connected }
            print("[RealtimeVoice] ✅ adapter connected, state=\(state)")
        } catch {
            print("[RealtimeVoice] ❌ adapter connect FAILED: \(error)")
            print("[RealtimeVoice] error type: \(type(of: error)), desc: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    /// CallKit의 didActivate에서 호출. 오디오 엔진을 시작합니다.
    func startAudioEngine() {
        guard let pipeline = audioPipeline else { return }
        // Bug fix: adapter를 캡처하여 fast reconnect 시 stale 오디오 방지
        let currentAdapter = adapter
        pipeline.start { [weak self] pcmData in
            guard self != nil else { return }
            await currentAdapter?.sendInputAudio(pcmData)
        }
    }

    /// 스피커폰 ↔ 수화기 전환.
    func setSpeakerEnabled(_ enabled: Bool) {
        isSpeakerOn = enabled
        audioPipeline?.setSpeakerEnabled(enabled)
    }

    /// CallKit의 didDeactivate에서 호출.
    func stopAudioEngine() {
        audioPipeline?.stop()
    }

    /// 통화 종료. 모든 리소스를 정리합니다.
    func disconnect() {
        adapter?.disconnect()
        adapter = nil
        audioPipeline?.teardown()
        audioPipeline = nil
        isAssistantSpeaking = false
        state = .disconnected
    }

    // MARK: - Private: State Reset

    private func resetState() {
        transcript.removeAll()
        partialUserText = ""
        partialAssistantText = ""
        isAssistantSpeaking = false
        pendingUserEntryId = nil
        userTranscriptDeltaCount = 0
        speechStartedCount = 0
        speechStoppedCount = 0
        audioCommittedCount = 0
        echoDropCount = 0
    }

    // MARK: - Private: Playback Completion

    private func handleAllPlaybackFinished() {
        isAssistantSpeaking = false
        audioPipeline?.isEchoSuppressed = false
        print("[RealtimeVoice] mic re-enabled (all playback finished) — echoSuppressed=\(audioPipeline?.isEchoSuppressed ?? true), isAssistantSpeaking=\(isAssistantSpeaking)")
    }

    // MARK: - Translation

    private func fetchTranslation(for entryId: UUID, text: String) {
        Task { [weak self] in
            guard let translation = await PhoneCallAIService.translate(text: text) else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let idx = self.transcript.firstIndex(where: { $0.id == entryId }) {
                    self.transcript[idx].translation = translation
                }
            }
        }
    }
}

// MARK: - RealtimeProviderDelegate

extension RealtimeVoiceService: RealtimeProviderDelegate {

    func providerDidUpdateSession() {
        print("[RealtimeVoice] session updated")
    }

    func providerDidStartResponse(responseId: String?) {
        isAssistantSpeaking = true
        audioPipeline?.isEchoSuppressed = true
        partialAssistantText = ""
        print("[RealtimeVoice] response started id=\(responseId ?? "?")")
    }

    func providerDidReceiveAudio(base64PCM16: String) {
        guard isAssistantSpeaking else { return }
        audioPipeline?.enqueuePlayback(base64PCM16: base64PCM16)
    }

    func providerDidReceiveAssistantTranscriptDelta(_ delta: String) {
        partialAssistantText += delta
    }

    func providerDidCompleteAssistantTranscript(_ finalText: String) {
        let entry = TranscriptEntry(speaker: .assistant, text: finalText, createdAt: Date())
        transcript.append(entry)
        partialAssistantText = ""
        fetchTranslation(for: entry.id, text: finalText)
    }

    func providerDidCompleteResponse() {
        // 스피커 재생이 아직 남아있을 수 있음
        if let pipeline = audioPipeline, pipeline.pendingPlaybackCount > 0 {
            pipeline.isAwaitingPlaybackFinish = true
            print("[RealtimeVoice] response.done — awaiting \(pipeline.pendingPlaybackCount) buffers, echoSuppressed=\(pipeline.isEchoSuppressed), isMuted=\(pipeline.isMuted)")
        } else {
            isAssistantSpeaking = false
            audioPipeline?.isEchoSuppressed = false
            print("[RealtimeVoice] response.done — mic re-enabled immediately")
        }
    }

    func providerDidDetectSpeechStart() {
        speechStartedCount += 1
        print("[RealtimeVoice] speech_started #\(speechStartedCount) — assistantSpeaking=\(isAssistantSpeaking)")
        // barge-in: AI 발화 중이면 중단
        if isAssistantSpeaking {
            isAssistantSpeaking = false
            audioPipeline?.isEchoSuppressed = false
            audioPipeline?.cancelPlayback()
            // Bug fix: adapter를 캡처하여 swap 레이스 방지
            let currentAdapter = adapter
            Task { await currentAdapter?.interrupt() }
        }
    }

    func providerDidDetectSpeechStop() {
        speechStoppedCount += 1
        print("[RealtimeVoice] speech_stopped #\(speechStoppedCount)")
    }

    func providerDidCommitUserAudio(itemId: String?) {
        audioCommittedCount += 1
        print("[RealtimeVoice] audio committed #\(audioCommittedCount) — itemId=\(itemId ?? "?")")
        // placeholder entry 추가 (UI에서 user 말풍선이 AI보다 먼저 표시)
        let placeholder = TranscriptEntry(speaker: .user, text: "…", createdAt: Date())
        transcript.append(placeholder)
        pendingUserEntryId = placeholder.id
        partialUserText = ""
        userTranscriptDeltaCount = 0
    }

    func providerDidReceiveUserTranscriptDelta(_ delta: String) {
        userTranscriptDeltaCount += 1
        if let entryId = pendingUserEntryId,
           let idx = transcript.firstIndex(where: { $0.id == entryId }) {
            if transcript[idx].text == "…" {
                transcript[idx].text = delta
            } else {
                transcript[idx].text += delta
            }
        } else {
            partialUserText += delta
        }
    }

    func providerDidCompleteUserTranscript(_ finalText: String) {
        partialUserText = ""
        if let entryId = pendingUserEntryId,
           let idx = transcript.firstIndex(where: { $0.id == entryId }) {
            if finalText.isEmpty {
                transcript.remove(at: idx)
            } else {
                transcript[idx].text = finalText
                fetchTranslation(for: entryId, text: finalText)
            }
            pendingUserEntryId = nil
        } else if !finalText.isEmpty {
            let entry = TranscriptEntry(speaker: .user, text: finalText, createdAt: Date())
            transcript.append(entry)
            fetchTranslation(for: entry.id, text: finalText)
        }
    }

    func providerDidCreateConversationItem(itemId: String) {
        // context pruning은 adapter 내부에서 처리
    }

    func providerDidEncounterError(message: String, isFatal: Bool) {
        print("[RealtimeVoice] provider error (fatal=\(isFatal)): \(message)")
        if isFatal {
            state = .error(message)
        }
    }
}
