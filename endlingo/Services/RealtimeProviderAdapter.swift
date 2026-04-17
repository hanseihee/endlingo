import Foundation

// MARK: - Provider Adapter Protocol

/// 실시간 음성 전송 계층 추상화.
///
/// 책임:
/// - 네트워크 연결 수명 주기 (connect / disconnect)
/// - 마이크 PCM16 데이터 → 서버 전송
/// - 서버 오디오/텍스트 수신 → delegate 콜백
///
/// 비책임 (CallAudioPipeline이 소유):
/// - AVAudioEngine, mic tap, playback scheduling
@MainActor
protocol RealtimeProviderAdapter: AnyObject {
    /// 마이크 캡처에 사용할 PCM16 샘플레이트.
    var inputSampleRate: Double { get }
    /// 서버가 반환하는 오디오의 PCM16 샘플레이트.
    var outputSampleRate: Double { get }

    /// 서버에 연결하고 세션을 구성합니다.
    func connect(config: ProviderSessionConfig, delegate: RealtimeProviderDelegate) async throws
    /// 연결을 종료하고 리소스를 해제합니다.
    func disconnect()
    /// 마이크에서 캡처한 PCM16 LE mono 데이터를 서버로 전송합니다.
    func sendInputAudio(_ pcm16Data: Data) async
    /// AI 발화 중단 (barge-in). 서버에 cancel 이벤트를 보냅니다.
    func interrupt() async
}

// MARK: - Session Config

/// Provider adapter에 전달하는 세션 구성.
struct ProviderSessionConfig: Sendable {
    let instructions: String
    let voice: String
    let firstResponseInstructions: String
    /// Gemini 모델 이름.
    let geminiModel: String?

    init(
        instructions: String,
        voice: String,
        firstResponseInstructions: String,
        geminiModel: String? = nil
    ) {
        self.instructions = instructions
        self.voice = voice
        self.firstResponseInstructions = firstResponseInstructions
        self.geminiModel = geminiModel
    }
}

// MARK: - Provider Delegate

/// Provider adapter가 서버에서 수신한 이벤트를 RealtimeVoiceService에 전달하는 콜백 프로토콜.
@MainActor
protocol RealtimeProviderDelegate: AnyObject {
    /// 세션 구성이 서버에 반영되었음.
    func providerDidUpdateSession()
    /// AI 응답 생성이 시작됨.
    func providerDidStartResponse(responseId: String?)
    /// 서버에서 오디오 청크(Base64 PCM16)를 수신함.
    func providerDidReceiveAudio(base64PCM16: String)
    /// AI 텍스트 트랜스크립트 델타.
    func providerDidReceiveAssistantTranscriptDelta(_ delta: String)
    /// AI 텍스트 트랜스크립트 최종 확정.
    func providerDidCompleteAssistantTranscript(_ finalText: String)
    /// AI 응답이 완료됨 (오디오+텍스트 모두).
    func providerDidCompleteResponse()
    /// 사용자 발화 시작 감지 (VAD).
    func providerDidDetectSpeechStart()
    /// 사용자 발화 종료 감지.
    func providerDidDetectSpeechStop()
    /// 사용자 음성이 서버에 커밋됨.
    func providerDidCommitUserAudio(itemId: String?)
    /// 사용자 트랜스크립트 델타.
    func providerDidReceiveUserTranscriptDelta(_ delta: String)
    /// 사용자 트랜스크립트 최종 확정.
    func providerDidCompleteUserTranscript(_ finalText: String)
    /// 대화 아이템이 생성됨 (context pruning 용).
    func providerDidCreateConversationItem(itemId: String)
    /// 에러 발생. `fatal`이면 통화 종료, 아니면 로그만.
    func providerDidEncounterError(message: String, isFatal: Bool)
}
