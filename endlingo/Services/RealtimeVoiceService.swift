@preconcurrency import AVFoundation
import Foundation
import SwiftUI

/// OpenAI Realtime API WebSocket 클라이언트 + 양방향 PCM16 24kHz 오디오 파이프라인.
///
/// 책임:
/// - WebSocket 연결 수명 주기 (connect/disconnect)
/// - 마이크 캡처 → PCM16 24kHz 변환 → `input_audio_buffer.append` 송신
/// - `response.audio.delta` 수신 → Float32 PCM 변환 → AVAudioPlayerNode 재생
/// - 트랜스크립트 델타 수집 (사용자/AI 각각)
/// - Server VAD로 턴 감지 (OpenAI 측에서 자동)
///
/// 비책임 (CallKit이 소유):
/// - AVAudioSession 카테고리/활성화 — PhoneCallController의 didActivate/didDeactivate에서 처리
/// - 통화 UI 및 발신자 표시
@Observable
@MainActor
final class RealtimeVoiceService: NSObject {
    static let shared = RealtimeVoiceService()

    // MARK: - State

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
    var isMuted: Bool = false
    /// 스피커폰 모드 여부. true=라우드스피커, false=수화기(이어피스).
    /// CallKit `.voiceChat` 모드의 기본은 수화기이므로 앱은 통화 시작 시 스피커폰으로 override.
    private(set) var isSpeakerOn: Bool = true

    // MARK: - Session Config

    /// WebSocket 연결 시 사용할 모델.
    /// gpt-realtime은 GA 모델. Preview 모델 사용하려면 `gpt-4o-realtime-preview`.
    private let model = "gpt-realtime"
    private let realtimeURL = "wss://api.openai.com/v1/realtime"
    private let sampleRate: Double = 24_000

    // MARK: - WebSocket

    @ObservationIgnored private var webSocket: URLSessionWebSocketTask?
    @ObservationIgnored private var urlSession: URLSession?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?

    // MARK: - Audio

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private var micConverter: AVAudioConverter?
    @ObservationIgnored private var outputFormat: AVAudioFormat?
    @ObservationIgnored private var isEngineConfigured = false
    @ObservationIgnored private var pendingPlaybackBuffers: [AVAudioPCMBuffer] = []

    /// 현재 AI가 말하고 있는 응답의 id. interrupt 시 cancel 용도로 사용.
    @ObservationIgnored private var currentResponseId: String?
    @ObservationIgnored private var firstAudioLogged = false
    @ObservationIgnored private var firstMicChunkLogged = false
    @ObservationIgnored private var sessionUpdatedContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Lifecycle

    private override init() {
        super.init()
    }

    /// OpenAI Realtime API에 연결하고 세션을 구성합니다.
    /// - 선행 조건: AVAudioSession이 이미 `.playAndRecord` + `.voiceChat`로 활성화돼 있어야 함 (CallKit이 처리).
    func connect(
        scenario: PhoneCallScenario,
        level: EnglishLevel,
        nativeLanguage: String,
        ephemeralKey: String
    ) async {
        guard state != .connecting && state != .connected else { return }
        state = .connecting
        transcript.removeAll()
        partialUserText = ""
        partialAssistantText = ""
        isAssistantSpeaking = false
        currentResponseId = nil
        firstAudioLogged = false
        firstMicChunkLogged = false

        guard var urlComponents = URLComponents(string: realtimeURL) else {
            state = .error("invalid URL")
            return
        }
        urlComponents.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = urlComponents.url else {
            state = .error("invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(ephemeralKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        request.timeoutInterval = 30

        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: request)
        webSocket = task
        task.resume()

        // 수신 루프 시작
        startReceiveLoop()

        // session.update 전송
        await sendSessionUpdate(
            instructions: scenario.instructions(for: level, nativeLanguage: nativeLanguage),
            voice: scenario.voice
        )

        // session.updated 수신 대기 (최대 3초).
        // instructions가 서버에 반영되기 전에 response.create가 처리되면
        // AI가 기본 모드로 떨어져 역할 무시하고 혼자 대화 생성하는 문제 방지.
        await waitForSessionUpdate(timeout: 3)

        // 첫 발화 트리거 — response-level instructions로 영어 시작 강제
        await sendEvent([
            "type": "response.create",
            "response": [
                "modalities": ["audio", "text"],
                "instructions": scenario.firstResponseInstructions
            ]
        ])

        state = .connected
    }

    private func waitForSessionUpdate(timeout seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionUpdatedContinuation = continuation
            // timeout 감시 — `session.updated` 이벤트 또는 error 이벤트로 먼저 resume
            // 되면 여기서 continuation을 다시 resume 하지 않도록 nil 체크로 가드.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, let pending = self.sessionUpdatedContinuation else { return }
                self.sessionUpdatedContinuation = nil
                print("[RealtimeVoice] session.updated wait timed out")
                pending.resume()
            }
        }
    }

    /// CallKit의 provider:didActivate에서 호출. 오디오 엔진을 시작하고 마이크 탭을 설치합니다.
    func startAudioEngine() {
        configureEngineIfNeeded()
        installMicTap()

        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            if !playerNode.isPlaying {
                playerNode.play()
            }
            // 큐에 쌓인 재생 버퍼 flush
            flushPendingPlayback()
            // 기본 출력을 스피커폰으로 설정 (.voiceChat 모드의 기본은 수화기)
            applySpeakerRoute()
            print("[RealtimeVoice] engine started — running=\(audioEngine.isRunning), player=\(playerNode.isPlaying), mic hz=\(audioEngine.inputNode.outputFormat(forBus: 0).sampleRate), speaker=\(isSpeakerOn)")
        } catch {
            print("[RealtimeVoice] engine start failed: \(error.localizedDescription)")
            state = .error("audio engine start failed: \(error.localizedDescription)")
        }
    }

    /// 스피커폰 ↔ 수화기 전환. 통화 중 언제든 호출 가능.
    func setSpeakerEnabled(_ enabled: Bool) {
        isSpeakerOn = enabled
        applySpeakerRoute()
    }

    private func applySpeakerRoute() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
            print("[RealtimeVoice] audio route → \(isSpeakerOn ? "speaker" : "receiver")")
        } catch {
            print("[RealtimeVoice] audio route override failed: \(error.localizedDescription)")
        }
    }

    /// CallKit의 provider:didDeactivate에서 호출. 오디오 엔진을 정지합니다.
    func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            playerNode.stop()
            audioEngine.stop()
        }
    }

    /// 통화 종료. WebSocket과 오디오를 모두 정리합니다.
    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        stopAudioEngine()
        pendingPlaybackBuffers.removeAll()
        isAssistantSpeaking = false
        state = .disconnected
    }

    // MARK: - Audio Engine Config

    private func configureEngineIfNeeded() {
        guard !isEngineConfigured else { return }
        guard let playerFmt = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else { return }
        outputFormat = playerFmt

        // NOTE: setVoiceProcessingEnabled(true)는 사용하지 않음.
        // CallKit의 AVAudioSession mode `.voiceChat`이 이미 시스템 레벨 AEC/NS를
        // 수행하므로 중복 활성화 시 오디오 파이프라인이 꼬여 AI 음성이 안 들리고
        // 마이크 포맷이 16kHz로 강제 변경되는 회귀가 발생.

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFmt)
        isEngineConfigured = true
    }

    private func installMicTap() {
        let inputNode = audioEngine.inputNode
        // 기존 탭 제거 후 재설치 (연속 통화 대비)
        inputNode.removeTap(onBus: 0)

        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else { return }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else { return }

        micConverter = AVAudioConverter(from: hwFormat, to: targetFormat)
        guard let converter = micConverter else { return }

        // 하드웨어 기준 bufferSize 2048~4096 권장. 너무 작으면 CPU 부담.
        let bufferSize: AVAudioFrameCount = 2048

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            // tap 콜백은 audio render thread. converter는 캡처값(참조)으로 사용.
            guard let base64 = Self.convertToPCM16Base64(input: buffer, converter: converter, targetFormat: targetFormat) else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self, !self.isMuted else { return }
                if !self.firstMicChunkLogged {
                    self.firstMicChunkLogged = true
                    print("[RealtimeVoice] first mic chunk sent (b64 len=\(base64.count))")
                }
                await self.sendEvent([
                    "type": "input_audio_buffer.append",
                    "audio": base64
                ])
            }
        }
    }

    // MARK: - Mic Capture → PCM16 Base64

    /// AVAudioPCMBuffer (하드웨어 Float32) → 24kHz Int16 mono → Base64 string.
    /// Audio render thread에서 호출되므로 순수 함수로 유지합니다.
    nonisolated private static func convertToPCM16Base64(
        input: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> String? {
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 16)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return nil
        }

        var error: NSError?
        var provided = false
        converter.convert(to: outBuffer, error: &error) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return input
        }

        guard error == nil,
              let int16Ptr = outBuffer.int16ChannelData?[0],
              outBuffer.frameLength > 0 else {
            return nil
        }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Ptr, count: byteCount)
        return data.base64EncodedString()
    }

    // MARK: - Playback: Base64 PCM16 → AVAudioPCMBuffer

    private func enqueuePlaybackChunk(base64: String) {
        // barge-in으로 isAssistantSpeaking이 false면 이후 도착한 잔여 delta 무시
        guard isAssistantSpeaking else { return }
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }
        guard let playerFmt = outputFormat else { return }

        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playerFmt, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let i16 = raw.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let out = buffer.floatChannelData?[0] else { return }
            let scale = Float(1.0 / 32768.0)
            for i in 0..<Int(frameCount) {
                out[i] = Float(i16[i]) * scale
            }
        }

        if audioEngine.isRunning && playerNode.engine != nil {
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        } else {
            pendingPlaybackBuffers.append(buffer)
        }
    }

    private func flushPendingPlayback() {
        guard !pendingPlaybackBuffers.isEmpty, audioEngine.isRunning else { return }
        for buffer in pendingPlaybackBuffers {
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        }
        pendingPlaybackBuffers.removeAll()
    }

    // MARK: - Translation

    /// 확정된 transcript entry를 네이티브 언어로 번역해 UI에 실시간 반영.
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

    private func cancelPlayback() {
        playerNode.stop()
        pendingPlaybackBuffers.removeAll()
        if audioEngine.isRunning {
            playerNode.play()
        }
    }

    // MARK: - WebSocket Send/Receive

    private func sendSessionUpdate(instructions: String, voice: String) async {
        // 주의: Swift Double(0.8)은 JSON 직렬화 시 0.80000000000000004처럼
        // 17 decimal places로 serialize되어 OpenAI가 거부합니다.
        // 따라서 temperature/threshold 같은 float 값은 NSNumber로 명시 정밀도 지정.
        let sessionConfig: [String: Any] = [
            "modalities": ["text", "audio"],
            "instructions": instructions,
            "voice": voice,
            "input_audio_format": "pcm16",
            "output_audio_format": "pcm16",
            "input_audio_transcription": ["model": "whisper-1"],
            "turn_detection": [
                "type": "server_vad",
                // float에서 정확히 표현되는 값만 사용 (0.3, 0.6 등은 17자리 확장됨).
                // 0.25 = 2^-2로 정확. 기본값 0.5보다 민감해 barge-in 감도 향상.
                "threshold": 0.25,
                "prefix_padding_ms": 300,
                "silence_duration_ms": 500,
                "create_response": true
            ]
            // temperature는 생략 — OpenAI 기본값(0.8) 사용
        ]
        await sendEvent([
            "type": "session.update",
            "session": sessionConfig
        ])
    }

    private func sendEvent(_ dict: [String: Any]) async {
        guard let webSocket else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        do {
            try await webSocket.send(.string(str))
        } catch {
            print("[RealtimeVoice] send failed: \(error.localizedDescription)")
            state = .error("send failed: \(error.localizedDescription)")
        }
    }

    private func startReceiveLoop() {
        receiveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let ws = self.webSocket else { break }
                do {
                    let message = try await ws.receive()
                    await self.handleMessage(message)
                } catch {
                    if self.state == .connected || self.state == .connecting {
                        self.state = .error(error.localizedDescription)
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }

        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "session.created":
            print("[RealtimeVoice] session.created")

        case "session.updated":
            print("[RealtimeVoice] session.updated ← instructions 반영 완료")
            if let cont = sessionUpdatedContinuation {
                sessionUpdatedContinuation = nil
                cont.resume()
            }

        case "response.created":
            if let response = obj["response"] as? [String: Any],
               let id = response["id"] as? String {
                currentResponseId = id
                print("[RealtimeVoice] response.created id=\(id)")
            }
            isAssistantSpeaking = true
            partialAssistantText = ""

        case "response.audio.delta":
            if let base64 = obj["delta"] as? String {
                if !firstAudioLogged {
                    firstAudioLogged = true
                    print("[RealtimeVoice] first audio delta received (len=\(base64.count))")
                }
                enqueuePlaybackChunk(base64: base64)
            }

        case "response.audio_transcript.delta":
            if let delta = obj["delta"] as? String {
                partialAssistantText += delta
            }

        case "response.audio_transcript.done":
            if let finalText = obj["transcript"] as? String, !finalText.isEmpty {
                let entry = TranscriptEntry(speaker: .assistant, text: finalText, createdAt: Date())
                transcript.append(entry)
                partialAssistantText = ""
                fetchTranslation(for: entry.id, text: finalText)
            }

        case "response.done":
            isAssistantSpeaking = false
            currentResponseId = nil

        case "conversation.item.input_audio_transcription.completed":
            let rawText = obj["transcript"] as? String ?? ""
            print("[RealtimeVoice] user transcription: \"\(rawText)\"")
            let finalText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalText.isEmpty {
                let entry = TranscriptEntry(speaker: .user, text: finalText, createdAt: Date())
                transcript.append(entry)
                partialUserText = ""
                fetchTranslation(for: entry.id, text: finalText)
            }

        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String {
                partialUserText += delta
            }

        case "input_audio_buffer.speech_started":
            print("[RealtimeVoice] speech_started (assistantSpeaking=\(isAssistantSpeaking))")
            // 사용자가 말하기 시작 → AI가 말 중이면 중단 (barge-in)
            if isAssistantSpeaking {
                isAssistantSpeaking = false  // 즉시 false로 → 이후 delta drop + 중복 cancel 방지
                cancelPlayback()
                await sendEvent(["type": "response.cancel"])
            }

        case "input_audio_buffer.speech_stopped":
            print("[RealtimeVoice] speech_stopped")

        case "input_audio_buffer.committed":
            print("[RealtimeVoice] audio committed")

        case "error":
            let errorDict = obj["error"] as? [String: Any]
            let message = errorDict?["message"] as? String ?? "unknown realtime error"
            let code = errorDict?["code"] as? String ?? "unknown"
            print("[RealtimeVoice] server error [\(code)]: \(message)")
            // 경량 오류는 통화 유지 (로그만). 치명적 오류만 state 변경.
            let ignorableCodes: Set<String> = [
                "response_cancel_not_active",  // barge-in 경합
                "input_audio_buffer_commit_empty"  // 침묵 commit
            ]
            if !ignorableCodes.contains(code) {
                state = .error(message)
            }
            // session.update가 에러로 거부되면 session.updated 이벤트가 오지 않으므로
            // 대기 중인 continuation을 여기서 해제해 connect() 흐름이 멈추지 않도록 함.
            if let cont = sessionUpdatedContinuation {
                sessionUpdatedContinuation = nil
                cont.resume()
            }

        default:
            break
        }
    }
}
