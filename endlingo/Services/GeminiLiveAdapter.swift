import Foundation
import Network

/// Gemini Live API 전송 계층 — Raw TCP+TLS + 수동 WebSocket 구현.
///
/// iOS의 `URLSessionWebSocketTask`와 `NWProtocolWebSocket`은
/// `generativelanguage.googleapis.com`에서 ALPN으로 HTTP/2를 협상하여 실패합니다.
/// 이 어댑터는 raw TCP+TLS 연결 후 HTTP/1.1 WebSocket upgrade를 수동으로 수행합니다.
///
/// 검증된 메시지 포맷 (macOS Swift CLI로 E2E 대화 성공):
/// - setup: camelCase (systemInstruction, generationConfig, speechConfig, ...)
/// - 첫 발화: `realtimeInput.text` (3.1은 clientContent 거부)
/// - 오디오 전송: `realtimeInput.audio` (mimeType, data)
/// - 서버 응답: `serverContent.modelTurn.parts[].inlineData`,
///            `serverContent.inputTranscription.text`,
///            `serverContent.outputTranscription.text`,
///            `serverContent.turnComplete`
@MainActor
final class GeminiLiveAdapter: RealtimeProviderAdapter {

    // MARK: - Protocol Conformance

    let inputSampleRate: Double = 16_000
    let outputSampleRate: Double = 24_000

    // MARK: - Config

    private let defaultModel = "gemini-3.1-flash-live-preview"
    private let apiKey: String = {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["API_KEY"] as? String else {
            fatalError("GoogleService-Info.plist에 API_KEY가 없습니다")
        }
        return key
    }()

    private let host = "generativelanguage.googleapis.com"

    // MARK: - State

    private weak var delegate: RealtimeProviderDelegate?
    private var connection: NWConnection?
    private var isConnected = false
    private var receiveTask: Task<Void, Never>?
    private var audioSendCount: Int = 0
    /// Fix #1: Upgrade 응답에 이어서 수신된 WebSocket 프레임 바이트.
    /// 서버가 TCP 세그먼트 경계를 header 중간에 두지 않아도 안전하게 처리.
    private var pendingFrameBuffer = Data()

    // Transcript 누적
    private var didNotifyResponseStart = false
    private var assistantTranscriptBuffer = ""
    private var userTranscriptBuffer = ""
    private var didCommitUserAudio = false

    // MARK: - Connect

    func connect(config: ProviderSessionConfig, delegate: RealtimeProviderDelegate) async throws {
        self.delegate = delegate
        resetState()

        let modelName = config.geminiModel ?? defaultModel
        let voiceName = mapVoice(config.voice)
        print("[GeminiAdapter] connecting — model=\(modelName), voice=\(voiceName)")

        // Fix #2: 모든 throw 경로에서 자원을 정리하도록 do-catch로 감싼다.
        // connect()가 실패하면 호출자(RealtimeVoiceService)가 disconnect()를 호출하지
        // 않고 state를 .error로만 설정하기 때문에 여기서 직접 cleanup.
        do {
            // 1) Raw TCP+TLS 연결
            let conn = try await connectTCP()
            self.connection = conn

            // 2) WebSocket 수동 upgrade
            let wsPath = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"
            try await performWebSocketUpgrade(conn: conn, path: wsPath)
            print("[GeminiAdapter] ✅ WebSocket connected")

            // 3) Setup 메시지 (transcription 활성화 — 사용자/AI 텍스트 동시 수신)
            let setup: [String: Any] = [
                "setup": [
                    "model": "models/\(modelName)",
                    "generationConfig": [
                        "responseModalities": ["AUDIO"],
                        "speechConfig": [
                            "voiceConfig": [
                                "prebuiltVoiceConfig": ["voiceName": voiceName]
                            ]
                        ]
                    ],
                    "systemInstruction": [
                        "parts": [["text": config.instructions]]
                    ],
                    "inputAudioTranscription": [:],
                    "outputAudioTranscription": [:]
                ]
            ]
            try await sendJSON(setup)

            // 4) setupComplete 대기 (Fix #3: 5초 하드 타임아웃 — CallKit 타임아웃 회피)
            let setupResponse = try await receiveJSONWithTimeout(seconds: 5)
            guard setupResponse["setupComplete"] != nil else {
                throw NSError(domain: "GeminiAdapter", code: -10, userInfo: [NSLocalizedDescriptionKey: "Missing setupComplete"])
            }
            print("[GeminiAdapter] ✅ setupComplete")

            isConnected = true
            delegate.providerDidUpdateSession()

            // 5) 수신 루프 시작 (이후 모든 서버 메시지는 비동기 처리)
            startReceiveLoop()

            // 6) 첫 발화 트리거 — realtimeInput.text (3.1 필수 포맷)
            let firstMsg: [String: Any] = [
                "realtimeInput": [
                    "text": config.firstResponseInstructions
                ]
            ]
            try await sendJSON(firstMsg)
            delegate.providerDidStartResponse(responseId: nil)
            print("[GeminiAdapter] first response triggered ✅")
        } catch {
            // 부분 연결/수신 루프 정리 후 에러를 재전파
            print("[GeminiAdapter] connect failed, cleaning up: \(error.localizedDescription)")
            cleanupOnConnectFailure()
            throw error
        }
    }

    /// connect() 도중 실패 시 호출. isConnected 플래그는 건드리지 않고
    /// (아직 false 상태) NWConnection과 receiveTask만 정리한다.
    private func cleanupOnConnectFailure() {
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
        delegate = nil
        pendingFrameBuffer = Data()
        isConnected = false  // Fix: cleanupOnConnectFailure도 isConnected 초기화
    }

    /// setupComplete 수신 전용 하드 타임아웃 대기.
    /// `NWConnection.receive`는 Task 취소를 관찰하지 않으므로,
    /// 타임아웃 시 `connection.cancel()`을 호출하여 receive 콜백에 에러를 유발한다.
    /// 그러면 receiveJSON()이 실제로 throw하고 task group이 정상 종료된다.
    private func receiveJSONWithTimeout(seconds: Double) async throws -> [String: Any] {
        // 별도 Task로 타이머 돌리면서 receiveJSON 대기.
        // 먼저 끝나는 쪽이 승리, receive 쪽이 타임아웃 나면 connection.cancel()로 강제 해제.
        let conn = connection  // cleanupOnConnectFailure 경합 방지를 위해 캡처
        return try await withThrowingTaskGroup(of: ReceiveResult.self) { group in
            group.addTask {
                let json = try await self.receiveJSON()
                return .json(json)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                // 타임아웃 → NWConnection 취소로 receive를 깨운다.
                conn?.cancel()
                return .timeout
            }
            defer { group.cancelAll() }
            for try await result in group {
                switch result {
                case .json(let j):
                    return j
                case .timeout:
                    // 타이머가 먼저 끝남 — receive는 곧 POSIX 취소 에러로 throw됨.
                    // 하지만 안전하게 명시적 timeout 에러를 던짐.
                    throw NSError(
                        domain: "GeminiAdapter",
                        code: -20,
                        userInfo: [NSLocalizedDescriptionKey: "setupComplete timed out after \(seconds)s"]
                    )
                }
            }
            throw NSError(domain: "GeminiAdapter", code: -21, userInfo: [NSLocalizedDescriptionKey: "Empty task group"])
        }
    }

    private enum ReceiveResult: @unchecked Sendable {
        case json([String: Any])
        case timeout
    }

    // MARK: - Disconnect

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        // WebSocket close frame (best-effort)
        if let conn = connection, isConnected {
            let closeFrame = buildCloseFrame(code: 1000)
            conn.send(content: closeFrame, completion: .contentProcessed { _ in })
        }
        connection?.cancel()
        connection = nil
        isConnected = false
        delegate = nil
        pendingFrameBuffer = Data()
        print("[GeminiAdapter] disconnected")
    }

    // MARK: - Send Audio

    func sendInputAudio(_ pcm16Data: Data) async {
        guard isConnected else { return }
        audioSendCount += 1
        if audioSendCount == 1 {
            print("[GeminiAdapter] first audio send — bytes=\(pcm16Data.count)")
        } else if audioSendCount % 50 == 0 {
            print("[GeminiAdapter] audio send #\(audioSendCount)")
        }
        let msg: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": pcm16Data.base64EncodedString()
                ]
            ]
        ]
        try? await sendJSON(msg)
    }

    // MARK: - Interrupt

    func interrupt() async {
        // Gemini는 barge-in을 서버 측에서 자동 처리
    }

    // MARK: - TCP+TLS Connection

    private func connectTCP() async throws -> NWConnection {
        let params = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        let conn = NWConnection(
            to: .hostPort(host: .init(host), port: .https),
            using: params
        )

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            conn.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    cont.resume()
                case .failed(let err):
                    resumed = true
                    cont.resume(throwing: err)
                case .waiting(let err):
                    resumed = true
                    cont.resume(throwing: err)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        // 이후 상태 변경은 에러만 delegate로 전달
        conn.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                Task { @MainActor [weak self] in
                    self?.delegate?.providerDidEncounterError(message: err.localizedDescription, isFatal: true)
                }
            }
        }

        return conn
    }

    // MARK: - Manual WebSocket Upgrade

    private func performWebSocketUpgrade(conn: NWConnection, path: String) async throws {
        let wsKey = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: \(wsKey)\r\n\r\n"

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: request.data(using: .utf8), completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }

        // Fix #1: 헤더 끝(\r\n\r\n)까지 누적 읽기. 한 read로 끝났다고 가정하지 않는다.
        // 최대 16KB 안에 헤더가 반드시 끝나야 함 (Google은 통상 ~400바이트).
        var buffer = Data()
        let headerEnd = Data([0x0D, 0x0A, 0x0D, 0x0A]) // "\r\n\r\n"
        while buffer.count < 16_384 {
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, err in
                    if let err { cont.resume(throwing: err); return }
                    cont.resume(returning: data ?? Data())
                }
            }
            if chunk.isEmpty {
                throw NSError(domain: "GeminiAdapter", code: -11, userInfo: [NSLocalizedDescriptionKey: "Connection closed during upgrade"])
            }
            buffer.append(chunk)
            if buffer.range(of: headerEnd) != nil { break }
        }

        guard let sepRange = buffer.range(of: headerEnd) else {
            throw NSError(domain: "GeminiAdapter", code: -12, userInfo: [NSLocalizedDescriptionKey: "Upgrade header too large"])
        }

        let headerData = buffer.subdata(in: 0..<sepRange.lowerBound)
        let leftover = buffer.subdata(in: sepRange.upperBound..<buffer.count)

        guard let headerStr = String(data: headerData, encoding: .utf8) else {
            throw NSError(domain: "GeminiAdapter", code: -13, userInfo: [NSLocalizedDescriptionKey: "Upgrade header not UTF-8"])
        }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw NSError(domain: "GeminiAdapter", code: -14, userInfo: [NSLocalizedDescriptionKey: "Missing status line"])
        }

        // 상태 라인 엄격 검증: "HTTP/1.1 101 Switching Protocols"
        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              (parts[0] == "HTTP/1.1" || parts[0] == "HTTP/1.0"),
              parts[1] == "101" else {
            throw NSError(
                domain: "GeminiAdapter",
                code: -15,
                userInfo: [NSLocalizedDescriptionKey: "WebSocket upgrade failed: \(statusLine.prefix(200))"]
            )
        }

        // Upgrade / Connection 헤더 검증 (대소문자 무시)
        let lowerLines = lines.dropFirst().map { $0.lowercased() }
        guard lowerLines.contains(where: { $0.hasPrefix("upgrade:") && $0.contains("websocket") }) else {
            throw NSError(domain: "GeminiAdapter", code: -16, userInfo: [NSLocalizedDescriptionKey: "Missing Upgrade: websocket header"])
        }
        guard lowerLines.contains(where: { $0.hasPrefix("connection:") && $0.contains("upgrade") }) else {
            throw NSError(domain: "GeminiAdapter", code: -17, userInfo: [NSLocalizedDescriptionKey: "Missing Connection: Upgrade header"])
        }

        // 헤더 이후 바이트가 있으면 첫 WebSocket 프레임의 일부 — 보존
        if !leftover.isEmpty {
            pendingFrameBuffer = leftover
        }
    }

    // MARK: - WebSocket Frame Send

    private func sendJSON(_ dict: [String: Any]) async throws {
        guard let conn = connection else { return }
        let data = try JSONSerialization.data(withJSONObject: dict)
        let frame = buildFrame(opcode: 0x1, data: data, mask: true)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: frame, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }

    private func receiveJSON() async throws -> [String: Any] {
        let data = try await receiveWebSocketMessage()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GeminiAdapter", code: -12, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        return json
    }

    // MARK: - WebSocket Frame Receive

    private func receiveWebSocketMessage() async throws -> Data {
        let header = try await readExact(2)
        let opcode = header[0] & 0x0F
        let masked = (header[1] & 0x80) != 0
        var payloadLength = UInt64(header[1] & 0x7F)

        if payloadLength == 126 {
            let ext = try await readExact(2)
            payloadLength = UInt64(ext[0]) << 8 | UInt64(ext[1])
        } else if payloadLength == 127 {
            let ext = try await readExact(8)
            payloadLength = 0
            for i in 0..<8 { payloadLength = payloadLength << 8 | UInt64(ext[i]) }
        }

        var maskKey: [UInt8] = []
        if masked {
            maskKey = Array(try await readExact(4))
        }

        // bounds check: Int 범위를 넘는 frame size는 거부 (overflow 방지)
        guard payloadLength <= UInt64(Int.max), payloadLength <= 16 * 1024 * 1024 else {
            throw NSError(domain: "GeminiAdapter", code: -22, userInfo: [NSLocalizedDescriptionKey: "Frame too large: \(payloadLength)"])
        }
        var payload = Data()
        if payloadLength > 0 {
            payload = try await readExact(Int(payloadLength))
            if masked {
                for i in 0..<payload.count { payload[i] ^= maskKey[i % 4] }
            }
        }

        // Close frame
        if opcode == 0x8 {
            let code = payload.count >= 2 ? (UInt16(payload[0]) << 8 | UInt16(payload[1])) : 0
            let reason = payload.count > 2 ? String(data: payload[2...], encoding: .utf8) ?? "" : ""
            throw NSError(domain: "GeminiAdapter", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "WebSocket closed [\(code)]: \(reason)"])
        }

        // Ping → Pong
        if opcode == 0x9 {
            let pong = buildFrame(opcode: 0xA, data: payload, mask: true)
            connection?.send(content: pong, completion: .contentProcessed { _ in })
            return try await receiveWebSocketMessage()
        }

        return payload
    }

    private func readExact(_ n: Int) async throws -> Data {
        guard let conn = connection else {
            throw NSError(domain: "GeminiAdapter", code: -30, userInfo: [NSLocalizedDescriptionKey: "No connection"])
        }

        // Fix #1: upgrade 이후 남아있던 바이트를 먼저 소진.
        // 필요 바이트 수가 부족하면 소켓에서 추가 read.
        if !pendingFrameBuffer.isEmpty {
            if pendingFrameBuffer.count >= n {
                let taken = pendingFrameBuffer.prefix(n)
                pendingFrameBuffer.removeFirst(n)
                return Data(taken)
            } else {
                let partial = pendingFrameBuffer
                pendingFrameBuffer = Data()
                let remaining = n - partial.count
                let rest = try await readFromSocket(conn: conn, n: remaining)
                return partial + rest
            }
        }

        return try await readFromSocket(conn: conn, n: n)
    }

    private func readFromSocket(conn: NWConnection, n: Int) async throws -> Data {
        return try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: n, maximumLength: n) { data, _, _, err in
                if let err { cont.resume(throwing: err); return }
                guard let d = data, d.count == n else {
                    cont.resume(throwing: NSError(domain: "GeminiAdapter", code: -31, userInfo: [NSLocalizedDescriptionKey: "Short read"]))
                    return
                }
                cont.resume(returning: d)
            }
        }
    }

    // MARK: - Frame Builders

    private func buildFrame(opcode: UInt8, data: Data, mask: Bool) -> Data {
        var frame = Data()
        frame.append(0x80 | opcode)
        let length = data.count
        let maskBit: UInt8 = mask ? 0x80 : 0

        if length < 126 {
            frame.append(maskBit | UInt8(length))
        } else if length < 65536 {
            frame.append(maskBit | 126)
            frame.append(UInt8(length >> 8))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(maskBit | 127)
            for i in (0..<8).reversed() {
                frame.append(UInt8((length >> (i * 8)) & 0xFF))
            }
        }

        if mask {
            let key = (0..<4).map { _ in UInt8.random(in: 0...255) }
            frame.append(contentsOf: key)
            for i in 0..<data.count {
                frame.append(data[i] ^ key[i % 4])
            }
        } else {
            frame.append(data)
        }

        return frame
    }

    private func buildCloseFrame(code: UInt16) -> Data {
        var payload = Data()
        payload.append(UInt8(code >> 8))
        payload.append(UInt8(code & 0xFF))
        return buildFrame(opcode: 0x8, data: payload, mask: true)
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                do {
                    let data = try await self.receiveWebSocketMessage()
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }
                    await MainActor.run { self.handleServerMessage(json) }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.delegate?.providerDidEncounterError(message: error.localizedDescription, isFatal: true)
                        }
                    }
                    break
                }
            }
        }
    }

    // MARK: - Message Handling

    private func handleServerMessage(_ msg: [String: Any]) {
        if let sc = msg["serverContent"] as? [String: Any] {
            handleServerContent(sc)
        }
        // sessionResumptionUpdate, usageMetadata 등은 무시
    }

    private func handleServerContent(_ content: [String: Any]) {
        // Interrupted — 서버가 감지한 사용자 발화 시작
        if content["interrupted"] as? Bool == true {
            didNotifyResponseStart = false
            assistantTranscriptBuffer = ""
            delegate?.providerDidDetectSpeechStart()
        }

        // Model turn (오디오 파트)
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            if !didNotifyResponseStart {
                didNotifyResponseStart = true
                delegate?.providerDidStartResponse(responseId: nil)
            }
            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let base64 = inlineData["data"] as? String {
                    delegate?.providerDidReceiveAudio(base64PCM16: base64)
                }
                // TextPart는 무시 — 실제 발화는 outputTranscription으로 옴
            }
        }

        // 사용자 입력 트랜스크립트
        if let input = content["inputTranscription"] as? [String: Any],
           let text = input["text"] as? String, !text.isEmpty {
            if !didCommitUserAudio {
                didCommitUserAudio = true
                delegate?.providerDidCommitUserAudio(itemId: nil)
            }
            userTranscriptBuffer += text
            delegate?.providerDidReceiveUserTranscriptDelta(text)
        }

        // AI 출력 트랜스크립트
        if let output = content["outputTranscription"] as? [String: Any],
           let text = output["text"] as? String, !text.isEmpty {
            assistantTranscriptBuffer += text
            delegate?.providerDidReceiveAssistantTranscriptDelta(text)
        }

        // Turn complete
        if content["turnComplete"] as? Bool == true {
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
        pendingFrameBuffer = Data()
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
