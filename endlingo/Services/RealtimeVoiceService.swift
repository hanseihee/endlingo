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
        let createdAt: Date
    }

    private(set) var state: State = .idle
    private(set) var isAssistantSpeaking: Bool = false
    private(set) var transcript: [TranscriptEntry] = []
    private(set) var partialUserText: String = ""
    private(set) var partialAssistantText: String = ""
    var isMuted: Bool = false

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
        } catch {
            state = .error("audio engine start failed: \(error.localizedDescription)")
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

    private func cancelPlayback() {
        playerNode.stop()
        pendingPlaybackBuffers.removeAll()
        if audioEngine.isRunning {
            playerNode.play()
        }
    }

    // MARK: - WebSocket Send/Receive

    private func sendSessionUpdate(instructions: String, voice: String) async {
        let sessionConfig: [String: Any] = [
            "modalities": ["text", "audio"],
            "instructions": instructions,
            "voice": voice,
            "input_audio_format": "pcm16",
            "output_audio_format": "pcm16",
            "input_audio_transcription": ["model": "whisper-1"],
            "turn_detection": [
                "type": "server_vad",
                "threshold": 0.5,
                "prefix_padding_ms": 300,
                "silence_duration_ms": 600,
                "create_response": true
            ],
            "temperature": 0.8
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
        case "session.created", "session.updated":
            break

        case "response.created":
            if let response = obj["response"] as? [String: Any],
               let id = response["id"] as? String {
                currentResponseId = id
            }
            isAssistantSpeaking = true
            partialAssistantText = ""

        case "response.audio.delta":
            if let base64 = obj["delta"] as? String {
                enqueuePlaybackChunk(base64: base64)
            }

        case "response.audio_transcript.delta":
            if let delta = obj["delta"] as? String {
                partialAssistantText += delta
            }

        case "response.audio_transcript.done":
            if let finalText = obj["transcript"] as? String, !finalText.isEmpty {
                transcript.append(TranscriptEntry(speaker: .assistant, text: finalText, createdAt: Date()))
                partialAssistantText = ""
            }

        case "response.done":
            isAssistantSpeaking = false
            currentResponseId = nil

        case "conversation.item.input_audio_transcription.completed":
            if let finalText = obj["transcript"] as? String, !finalText.isEmpty {
                transcript.append(TranscriptEntry(speaker: .user, text: finalText, createdAt: Date()))
                partialUserText = ""
            }

        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String {
                partialUserText += delta
            }

        case "input_audio_buffer.speech_started":
            // 사용자가 말하기 시작 → AI가 말 중이면 중단 (barge-in)
            if isAssistantSpeaking {
                cancelPlayback()
                if let id = currentResponseId {
                    await sendEvent(["type": "response.cancel"])
                    _ = id
                }
            }

        case "input_audio_buffer.speech_stopped", "input_audio_buffer.committed":
            break

        case "error":
            let errorDict = obj["error"] as? [String: Any]
            let message = errorDict?["message"] as? String ?? "unknown realtime error"
            let code = errorDict?["code"] as? String ?? "unknown"
            print("[RealtimeVoice] server error [\(code)]: \(message)")
            state = .error(message)

        default:
            break
        }
    }
}
