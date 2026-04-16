import FirebaseAI
import Foundation

/// Gemini Live API 전송 계층 (Firebase AI SDK).
///
/// Firebase AI의 `LiveGenerativeModel`을 통해 Gemini 서버와 양방향 오디오 스트리밍.
/// WebSocket 관리는 Firebase SDK가 내부에서 처리합니다.
@MainActor
final class GeminiLiveAdapter: RealtimeProviderAdapter {

    let inputSampleRate: Double = 16_000
    let outputSampleRate: Double = 24_000

    private weak var delegate: RealtimeProviderDelegate?
    private var session: LiveSession?
    private var isConnected = false
    private var responseListenTask: Task<Void, Never>?
    private var audioSendCount: Int = 0

    // Transcript 누적
    private var didNotifyResponseStart = false
    private var assistantTranscriptBuffer = ""
    private var userTranscriptBuffer = ""
    private var didCommitUserAudio = false

    // MARK: - Connect

    func connect(config: ProviderSessionConfig, delegate: RealtimeProviderDelegate) async throws {
        self.delegate = delegate
        resetState()

        let modelName = config.geminiModel ?? "gemini-2.5-flash-native-audio-preview-12-2025"
        let voiceName = mapVoice(config.voice)

        let liveModel = FirebaseAI.firebaseAI(backend: .googleAI()).liveModel(
            modelName: modelName,
            generationConfig: LiveGenerationConfig(
                responseModalities: [.audio],
                speech: SpeechConfig(voiceName: voiceName),
                inputAudioTranscription: AudioTranscriptionConfig(),
                outputAudioTranscription: AudioTranscriptionConfig()
            ),
            systemInstruction: ModelContent(role: "system", parts: config.instructions)
        )

        print("[GeminiAdapter] connecting — model=\(modelName), voice=\(voiceName)")

        let session = try await liveModel.connect()
        self.session = session
        isConnected = true
        delegate.providerDidUpdateSession()
        print("[GeminiAdapter] ✅ connected")

        startResponseListener()

        guard let activeSession = self.session else { return }
        print("[GeminiAdapter] sending first response…")
        await activeSession.sendContent(config.firstResponseInstructions, turnComplete: true)
        delegate.providerDidStartResponse(responseId: nil)
        print("[GeminiAdapter] first response triggered ✅")
    }

    // MARK: - Disconnect

    func disconnect() {
        responseListenTask?.cancel()
        responseListenTask = nil
        let s = session
        session = nil
        isConnected = false
        delegate = nil
        Task { await s?.close() }
        print("[GeminiAdapter] disconnected")
    }

    // MARK: - Send Audio

    func sendInputAudio(_ pcm16Data: Data) async {
        guard isConnected, let session else { return }
        audioSendCount += 1
        if audioSendCount == 1 {
            print("[GeminiAdapter] first audio send — bytes=\(pcm16Data.count)")
        } else if audioSendCount % 50 == 0 {
            print("[GeminiAdapter] audio send #\(audioSendCount)")
        }
        await session.sendAudioRealtime(pcm16Data)
    }

    // MARK: - Interrupt

    func interrupt() async {
        print("[GeminiAdapter] interrupt — server handles barge-in")
    }

    // MARK: - Response Listener

    private func startResponseListener() {
        guard let session else { return }
        responseListenTask = Task { [weak self] in
            do {
                for try await message in session.responses {
                    guard let self, !Task.isCancelled else { break }
                    self.handleMessage(message)
                }
                if let self, self.isConnected {
                    self.delegate?.providerDidEncounterError(message: "Gemini session ended", isFatal: true)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                print("[GeminiAdapter] response error: \(error.localizedDescription)")
                self.delegate?.providerDidEncounterError(message: error.localizedDescription, isFatal: true)
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: LiveServerMessage) {
        switch message.payload {
        case .content(let content):
            handleContent(content)
        case .goingAwayNotice:
            print("[GeminiAdapter] goingAway notice")
            delegate?.providerDidEncounterError(message: "Gemini session ending soon", isFatal: false)
        case .toolCall, .toolCallCancellation:
            break
        }
    }

    private func handleContent(_ content: LiveServerContent) {
        if content.wasInterrupted {
            print("[GeminiAdapter] interrupted")
            didNotifyResponseStart = false
            assistantTranscriptBuffer = ""
            delegate?.providerDidDetectSpeechStart()
        }

        if let modelTurn = content.modelTurn {
            if !didNotifyResponseStart {
                didNotifyResponseStart = true
                delegate?.providerDidStartResponse(responseId: nil)
            }
            for part in modelTurn.parts {
                if let inlineData = part as? InlineDataPart {
                    let base64 = inlineData.data.base64EncodedString()
                    delegate?.providerDidReceiveAudio(base64PCM16: base64)
                }
                // TextPart는 Gemini의 내부 thinking 텍스트 — UI에 표시하지 않음.
                // 실제 발화 텍스트는 outputAudioTranscription에서 전달됨.
            }
        }

        if let inputTranscript = content.inputAudioTranscription,
           let text = inputTranscript.text, !text.isEmpty {
            if !didCommitUserAudio {
                didCommitUserAudio = true
                delegate?.providerDidCommitUserAudio(itemId: nil)
            }
            userTranscriptBuffer += text
            delegate?.providerDidReceiveUserTranscriptDelta(text)
        }

        if let outputTranscript = content.outputAudioTranscription,
           let text = outputTranscript.text, !text.isEmpty {
            assistantTranscriptBuffer += text
            delegate?.providerDidReceiveAssistantTranscriptDelta(text)
        }

        if content.isTurnComplete {
            if !assistantTranscriptBuffer.isEmpty {
                delegate?.providerDidCompleteAssistantTranscript(assistantTranscriptBuffer)
                assistantTranscriptBuffer = ""
            }
            if !userTranscriptBuffer.isEmpty {
                delegate?.providerDidCompleteUserTranscript(userTranscriptBuffer)
                userTranscriptBuffer = ""
                didCommitUserAudio = false
            }
            didNotifyResponseStart = false
            delegate?.providerDidCompleteResponse()
        }
    }

    // MARK: - Helpers

    private func resetState() {
        audioSendCount = 0
        didNotifyResponseStart = false
        assistantTranscriptBuffer = ""
        userTranscriptBuffer = ""
        didCommitUserAudio = false
    }

    private func mapVoice(_ openAIVoice: String) -> String {
        switch openAIVoice {
        case "alloy": return "Kore"
        case "echo": return "Charon"
        case "fable": return "Fenrir"
        case "onyx": return "Puck"
        case "nova": return "Aoede"
        case "shimmer": return "Leda"
        case "ash": return "Orus"
        case "sage": return "Vale"
        case "ballad": return "Kore"
        case "coral": return "Aoede"
        case "verse": return "Puck"
        default: return "Kore"
        }
    }
}
