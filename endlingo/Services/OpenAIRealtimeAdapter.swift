import Foundation

/// OpenAI Realtime API WebSocket 전송 계층.
///
/// RealtimeVoiceService에서 추출한 OpenAI 전용 로직:
/// - WebSocket 연결/해제 (`wss://api.openai.com/v1/realtime`)
/// - `session.update`, `response.create`, `input_audio_buffer.append` 전송
/// - 서버 이벤트 파싱 → `RealtimeProviderDelegate` 콜백
/// - conversation context pruning
///
/// 오디오 캡처/재생은 `CallAudioPipeline`이 처리하므로 여기서는 다루지 않습니다.
@MainActor
final class OpenAIRealtimeAdapter: RealtimeProviderAdapter {

    // MARK: - Protocol Conformance

    let inputSampleRate: Double = 24_000
    let outputSampleRate: Double = 24_000

    // MARK: - Private

    private let model = "gpt-realtime-mini"
    private let realtimeURL = "wss://api.openai.com/v1/realtime"

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveTask: Task<Void, Never>?
    private weak var delegate: RealtimeProviderDelegate?

    /// session.updated 이벤트 대기용 continuation.
    private var sessionUpdatedContinuation: CheckedContinuation<Void, Never>?

    /// 서버 conversation context의 item_id FIFO.
    private var conversationItemIds: [String] = []
    private let maxContextItems = 10

    /// 현재 AI가 말하고 있는 응답의 id.
    private var currentResponseId: String?

    // Diagnostic counters
    private var sendDropNoWSCount: Int = 0
    private var firstAudioLogged = false

    // MARK: - Connect

    func connect(config: ProviderSessionConfig, delegate: RealtimeProviderDelegate) async throws {
        self.delegate = delegate
        conversationItemIds = []
        currentResponseId = nil
        sendDropNoWSCount = 0
        firstAudioLogged = false

        guard let ephemeralKey = config.ephemeralKey else {
            delegate.providerDidEncounterError(message: "ephemeral key missing", isFatal: true)
            return
        }

        guard var urlComponents = URLComponents(string: realtimeURL) else {
            delegate.providerDidEncounterError(message: "invalid URL", isFatal: true)
            return
        }
        urlComponents.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = urlComponents.url else {
            delegate.providerDidEncounterError(message: "invalid URL", isFatal: true)
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

        startReceiveLoop()

        // session.update 전송
        await sendSessionUpdate(instructions: config.instructions, voice: config.voice)

        // session.updated 대기 (최대 3초)
        await waitForSessionUpdate(timeout: 3)

        // 첫 발화 트리거
        await sendEvent([
            "type": "response.create",
            "response": [
                "modalities": ["audio", "text"],
                "instructions": config.firstResponseInstructions
            ]
        ])
    }

    // MARK: - Disconnect

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        delegate = nil
    }

    // MARK: - Send Audio

    func sendInputAudio(_ pcm16Data: Data) async {
        let base64 = pcm16Data.base64EncodedString()
        await sendEvent([
            "type": "input_audio_buffer.append",
            "audio": base64
        ])
    }

    // MARK: - Interrupt

    func interrupt() async {
        await sendEvent(["type": "response.cancel"])
    }

    // MARK: - Private: Session Update

    private func sendSessionUpdate(instructions: String, voice: String) async {
        let sessionConfig: [String: Any] = [
            "modalities": ["text", "audio"],
            "instructions": instructions,
            "voice": voice,
            "input_audio_format": "pcm16",
            "output_audio_format": "pcm16",
            "input_audio_transcription": [
                "model": "whisper-1",
                "language": "en"
            ],
            "turn_detection": [
                "type": "server_vad",
                "threshold": 0.25,
                "prefix_padding_ms": 300,
                "silence_duration_ms": 900,
                "create_response": true
            ],
            "temperature": 0.875
        ]
        await sendEvent([
            "type": "session.update",
            "session": sessionConfig
        ])
    }

    private func waitForSessionUpdate(timeout seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionUpdatedContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, let pending = self.sessionUpdatedContinuation else { return }
                self.sessionUpdatedContinuation = nil
                print("[OpenAIAdapter] session.updated wait timed out")
                pending.resume()
            }
        }
    }

    // MARK: - Private: WebSocket Send/Receive

    private func sendEvent(_ dict: [String: Any]) async {
        guard let webSocket else {
            sendDropNoWSCount += 1
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        do {
            try await webSocket.send(.string(str))
        } catch {
            let t = dict["type"] as? String ?? "?"
            print("[OpenAIAdapter] send failed (type=\(t)): \(error.localizedDescription)")
            delegate?.providerDidEncounterError(message: "send failed: \(error.localizedDescription)", isFatal: true)
        }
    }

    private func startReceiveLoop() {
        receiveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let ws = self.webSocket else { break }
                do {
                    let message = try await ws.receive()
                    self.handleMessage(message)
                } catch {
                    self.delegate?.providerDidEncounterError(message: error.localizedDescription, isFatal: true)
                    break
                }
            }
        }
    }

    // MARK: - Private: Message Handling

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
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
        case "conversation.item.created":
            if let item = obj["item"] as? [String: Any],
               let itemId = item["id"] as? String {
                delegate?.providerDidCreateConversationItem(itemId: itemId)
                conversationItemIds.append(itemId)
                Task { await self.pruneOldItemsIfNeeded() }
            }

        case "session.created":
            print("[OpenAIAdapter] session.created")

        case "session.updated":
            print("[OpenAIAdapter] session.updated")
            if let cont = sessionUpdatedContinuation {
                sessionUpdatedContinuation = nil
                cont.resume()
            }
            delegate?.providerDidUpdateSession()

        case "response.created":
            var responseId: String?
            if let response = obj["response"] as? [String: Any],
               let id = response["id"] as? String {
                currentResponseId = id
                responseId = id
            }
            delegate?.providerDidStartResponse(responseId: responseId)

        case "response.audio.delta":
            if let base64 = obj["delta"] as? String {
                if !firstAudioLogged {
                    firstAudioLogged = true
                    print("[OpenAIAdapter] first audio delta (len=\(base64.count))")
                }
                delegate?.providerDidReceiveAudio(base64PCM16: base64)
            }

        case "response.audio_transcript.delta":
            if let delta = obj["delta"] as? String {
                delegate?.providerDidReceiveAssistantTranscriptDelta(delta)
            }

        case "response.audio_transcript.done":
            if let finalText = obj["transcript"] as? String, !finalText.isEmpty {
                delegate?.providerDidCompleteAssistantTranscript(finalText)
            }

        case "response.done":
            currentResponseId = nil
            delegate?.providerDidCompleteResponse()

        case "conversation.item.input_audio_transcription.completed":
            let rawText = obj["transcript"] as? String ?? ""
            let finalText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalText.isEmpty {
                delegate?.providerDidCompleteUserTranscript(finalText)
            } else {
                // 무음 인식 — 빈 문자열로 전달하여 placeholder 제거
                delegate?.providerDidCompleteUserTranscript("")
            }

        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String {
                delegate?.providerDidReceiveUserTranscriptDelta(delta)
            }

        case "conversation.item.input_audio_transcription.failed":
            let errorDict = obj["error"] as? [String: Any]
            let message = errorDict?["message"] as? String ?? "unknown"
            print("[OpenAIAdapter] user transcription FAILED: \(message)")

        case "input_audio_buffer.speech_started":
            delegate?.providerDidDetectSpeechStart()

        case "input_audio_buffer.speech_stopped":
            delegate?.providerDidDetectSpeechStop()

        case "input_audio_buffer.committed":
            let itemId = obj["item_id"] as? String
            delegate?.providerDidCommitUserAudio(itemId: itemId)

        case "error":
            let errorDict = obj["error"] as? [String: Any]
            let message = errorDict?["message"] as? String ?? "unknown realtime error"
            let code = errorDict?["code"] as? String ?? "unknown"
            print("[OpenAIAdapter] server error [\(code)]: \(message)")
            let ignorableCodes: Set<String> = [
                "response_cancel_not_active",
                "input_audio_buffer_commit_empty",
                "item_not_found",
                "item_truncate_invalid_audio_end_ms"
            ]
            let isFatal = !ignorableCodes.contains(code)
            delegate?.providerDidEncounterError(message: message, isFatal: isFatal)
            if let cont = sessionUpdatedContinuation {
                sessionUpdatedContinuation = nil
                cont.resume()
            }

        default:
            break
        }
    }

    // MARK: - Private: Context Pruning

    private func pruneOldItemsIfNeeded() async {
        var pruned = 0
        while conversationItemIds.count > maxContextItems {
            let oldestId = conversationItemIds.removeFirst()
            await sendEvent([
                "type": "conversation.item.delete",
                "item_id": oldestId
            ])
            pruned += 1
        }
        if pruned > 0 {
            print("[OpenAIAdapter] pruned \(pruned) items, remaining=\(conversationItemIds.count)")
        }
    }
}
