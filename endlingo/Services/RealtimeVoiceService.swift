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
    /// 비용 최적화: gpt-realtime-mini (gpt-realtime 대비 오디오 약 70% 저렴).
    /// 품질 저하 체감 시 `gpt-realtime`으로 복원. 최신 preview는 `gpt-4o-realtime-preview`.
    private let model = "gpt-realtime-mini"
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

    // MARK: - Diagnostic counters (마이크/전송/VAD 추적용)
    @ObservationIgnored private var micChunkCount: Int = 0
    @ObservationIgnored private var micDropMutedCount: Int = 0
    @ObservationIgnored private var micConvertFailCount: Int = 0
    @ObservationIgnored private var micPeakSum: Float = 0
    @ObservationIgnored private var micPeakMax: Float = 0
    @ObservationIgnored private var sendDropNoWSCount: Int = 0
    @ObservationIgnored private var userTranscriptDeltaCount: Int = 0
    @ObservationIgnored private var speechStartedCount: Int = 0
    @ObservationIgnored private var speechStoppedCount: Int = 0
    @ObservationIgnored private var audioCommittedCount: Int = 0
    /// AI 발화 중 echo로 추정해 OpenAI에 보내지 않고 drop한 마이크 chunk 수.
    @ObservationIgnored private var echoDropCount: Int = 0
    /// 사용자 발화가 committed된 직후 transcript 배열에 미리 추가한 placeholder entry id.
    /// whisper STT 결과(transcription.completed)가 도착하면 이 entry의 text를 업데이트.
    /// AI 응답보다 user 말풍선이 UI에서 먼저 보이게 하는 핵심 장치.
    @ObservationIgnored private var pendingUserEntryId: UUID?
    /// playerNode.scheduleBuffer가 실제 호출된 횟수 (재생 경로 진단용).
    @ObservationIgnored private var scheduleBufferCount: Int = 0
    /// pending queue에 쌓인 횟수 (엔진 미실행 상태에서 수신된 audio delta).
    @ObservationIgnored private var pendingQueuedCount: Int = 0
    /// 현재 playerNode에 스케줄되어 아직 스피커 재생이 끝나지 않은 버퍼 수.
    /// response.done 수신 시점에도 남아 있으면 모두 재생된 후 마이크 재개.
    @ObservationIgnored private var pendingPlaybackFinishesExpected: Int = 0
    /// response.done 이벤트를 받았는데 아직 스피커 재생이 남아있어 대기 중인 상태.
    @ObservationIgnored private var responseDoneAwaitingPlayback: Bool = false
    /// OpenAI가 보내는 오디오 원본 포맷 (24kHz int16 interleaved mono).
    @ObservationIgnored private var playbackSourceFormat: AVAudioFormat?
    /// 원본 포맷 → outputNode 실제 포맷 변환 컨버터 (VPIO가 output을 44100/stereo로 강제하는 경우 대응).
    @ObservationIgnored private var playbackConverter: AVAudioConverter?

    // MARK: - Lifecycle

    private override init() {
        super.init()
        // 엔진 configuration 변경 감지 — VPIO 활성화 후 format 재협상 시 발생 가능.
        // 발생 시 engine이 내부적으로 정지할 수 있으므로 로그로 추적.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                print("[RealtimeVoice] AVAudioEngineConfigurationChange — running=\(self.audioEngine.isRunning), player=\(self.playerNode.isPlaying)")
                // 구성 변경 후 엔진이 멈춘 경우 자동 재시작
                if !self.audioEngine.isRunning && self.state == .connected {
                    do {
                        try self.audioEngine.start()
                        if !self.playerNode.isPlaying { self.playerNode.play() }
                        print("[RealtimeVoice] engine auto-restarted after config change — running=\(self.audioEngine.isRunning)")
                    } catch {
                        print("[RealtimeVoice] engine auto-restart failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// OpenAI Realtime API에 연결하고 세션을 구성합니다.
    /// - 선행 조건: AVAudioSession이 이미 `.playAndRecord` + `.voiceChat`로 활성화돼 있어야 함 (CallKit이 처리).
    func connect(
        scenario: PhoneCallScenario,
        variant: ScenarioVariant,
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
        micChunkCount = 0
        micDropMutedCount = 0
        micConvertFailCount = 0
        micPeakSum = 0
        micPeakMax = 0
        sendDropNoWSCount = 0
        userTranscriptDeltaCount = 0
        speechStartedCount = 0
        speechStoppedCount = 0
        audioCommittedCount = 0
        echoDropCount = 0
        scheduleBufferCount = 0
        pendingQueuedCount = 0
        pendingPlaybackFinishesExpected = 0
        responseDoneAwaitingPlayback = false
        pendingUserEntryId = nil

        // 진단: 현재 마이크 권한 + AVAudioSession 상태 덤프
        let audioSession = AVAudioSession.sharedInstance()
        let permission: String
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permission = "granted"
        case .denied: permission = "denied"
        case .undetermined: permission = "undetermined"
        @unknown default: permission = "unknown"
        }
        let inputAvailable = audioSession.isInputAvailable
        let inputs = audioSession.availableInputs?.map { $0.portType.rawValue }.joined(separator: ",") ?? "-"
        print("[RealtimeVoice] connect start — micPermission=\(permission), inputAvail=\(inputAvailable), availInputs=[\(inputs)], category=\(audioSession.category.rawValue), mode=\(audioSession.mode.rawValue), sessionSR=\(audioSession.sampleRate), inputChannels=\(audioSession.inputNumberOfChannels)")

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

        // session.update 전송 — variant에서 확정된 persona/opening/situation 주입
        await sendSessionUpdate(
            instructions: scenario.instructions(for: level, nativeLanguage: nativeLanguage, variant: variant),
            voice: variant.voice
        )

        // session.updated 수신 대기 (최대 3초).
        // instructions가 서버에 반영되기 전에 response.create가 처리되면
        // AI가 기본 모드로 떨어져 역할 무시하고 혼자 대화 생성하는 문제 방지.
        await waitForSessionUpdate(timeout: 3)

        // 첫 발화 트리거 — variant의 opening line + 영어 강제
        await sendEvent([
            "type": "response.create",
            "response": [
                "modalities": ["audio", "text"],
                "instructions": variant.firstResponseInstructions
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

        // VPIO 활성화 후 format 재협상이 필요하므로 prepare로 그래프를 확정.
        audioEngine.prepare()

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
            let input = audioEngine.inputNode
            let output = audioEngine.outputNode
            let playerFmt = playerNode.outputFormat(forBus: 0)
            print("[RealtimeVoice] engine started — running=\(audioEngine.isRunning), player=\(playerNode.isPlaying), vpio=\(input.isVoiceProcessingEnabled), micIn=\(input.outputFormat(forBus: 0).sampleRate)/\(input.outputFormat(forBus: 0).channelCount), outputIn=\(output.inputFormat(forBus: 0).sampleRate)/\(output.inputFormat(forBus: 0).channelCount), playerFmt=\(playerFmt.sampleRate)/\(playerFmt.channelCount), speaker=\(isSpeakerOn)")
            if !audioEngine.isRunning {
                // start()가 throw 안 했는데 isRunning=false — 그래프 format 불일치로 내부 중단.
                // 재시도 1회 (일부 iOS 버전에서 prepare 타이밍 이슈 회피).
                print("[RealtimeVoice] WARNING engine.start() silent-fail, retrying once…")
                try? audioEngine.start()
                if !playerNode.isPlaying { playerNode.play() }
                print("[RealtimeVoice] retry result — running=\(audioEngine.isRunning), player=\(playerNode.isPlaying)")
                if !audioEngine.isRunning {
                    state = .error("audio engine failed to run after retry")
                }
            }
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

        // 1) VPIO 먼저 활성화 — inputNode/outputNode 포맷을 VPIO가 강제하는 값으로 확정시킴.
        //    `.voiceChat` + Remote I/O 조합만으로는 iOS 17+에서 installTap 콜백이 호출되지 않는
        //    회귀가 있어 반드시 필요. AGC는 residual echo 증폭 방지 위해 비활성화.
        do {
            try audioEngine.inputNode.setVoiceProcessingEnabled(true)
            audioEngine.inputNode.isVoiceProcessingAGCEnabled = false
            print("[RealtimeVoice] voice processing enabled — vpio=\(audioEngine.inputNode.isVoiceProcessingEnabled), agc=\(audioEngine.inputNode.isVoiceProcessingAGCEnabled)")
        } catch {
            print("[RealtimeVoice] setVoiceProcessingEnabled failed: \(error.localizedDescription)")
        }

        // 2) OpenAI가 전송하는 원본 포맷: 24kHz int16 interleaved mono
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else { return }
        playbackSourceFormat = sourceFormat

        // 3) outputNode의 실제 포맷 — VPIO 활성화 후 확정 (예: 44100/stereo Float32 non-interleaved)
        let outFmt = audioEngine.outputNode.inputFormat(forBus: 0)
        outputFormat = outFmt
        print("[RealtimeVoice] outputNode inputFormat — sr=\(outFmt.sampleRate), ch=\(outFmt.channelCount), common=\(outFmt.commonFormat.rawValue)")

        // 4) playerNode를 outputNode에 직접 연결 — mainMixer 우회.
        //    mainMixer를 통과시키면 24k/mono → 44.1k/stereo 두 단계 변환을 VPIO 상태에서
        //    처리하지 못해 engine이 silent-fail로 정지하는 회귀 발생.
        //    outputNode 포맷으로 attach하면 format 협상 없이 즉시 시작 가능.
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.outputNode, format: outFmt)
        playerNode.volume = 1.0
        print("[RealtimeVoice] playerNode → outputNode direct (fmt=\(outFmt.sampleRate)/\(outFmt.channelCount)), playerVol=\(playerNode.volume)")

        // 5) 원본 24k int16 mono → outputNode 포맷 변환용 컨버터
        playbackConverter = AVAudioConverter(from: sourceFormat, to: outFmt)
        if playbackConverter == nil {
            print("[RealtimeVoice] WARNING playbackConverter create failed (source=\(sourceFormat) → target=\(outFmt))")
        }

        isEngineConfigured = true
    }

    private func installMicTap() {
        let inputNode = audioEngine.inputNode
        // 기존 탭 제거 후 재설치 (연속 통화 대비)
        inputNode.removeTap(onBus: 0)

        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else {
            print("[RealtimeVoice] installMicTap aborted — hwFormat sampleRate=0 (inputNode not ready)")
            return
        }

        print("[RealtimeVoice] installMicTap hwFormat — sr=\(hwFormat.sampleRate), ch=\(hwFormat.channelCount), common=\(hwFormat.commonFormat.rawValue), interleaved=\(hwFormat.isInterleaved), vpio=\(inputNode.isVoiceProcessingEnabled)")

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            print("[RealtimeVoice] installMicTap aborted — targetFormat create failed")
            return
        }

        micConverter = AVAudioConverter(from: hwFormat, to: targetFormat)
        guard let converter = micConverter else {
            print("[RealtimeVoice] installMicTap aborted — converter create failed (hw=\(hwFormat) → target=\(targetFormat))")
            return
        }

        // 하드웨어 기준 bufferSize 2048~4096 권장. 너무 작으면 CPU 부담.
        let bufferSize: AVAudioFrameCount = 2048

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            // tap 콜백은 audio render thread. converter는 캡처값(참조)으로 사용.
            guard let result = Self.convertToPCM16Base64(input: buffer, converter: converter, targetFormat: targetFormat) else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.micConvertFailCount += 1
                    if self.micConvertFailCount == 1 || self.micConvertFailCount % 50 == 0 {
                        print("[RealtimeVoice] mic convert fail count=\(self.micConvertFailCount)")
                    }
                }
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isMuted {
                    self.micDropMutedCount += 1
                    if self.micDropMutedCount == 1 || self.micDropMutedCount % 100 == 0 {
                        print("[RealtimeVoice] mic muted drop count=\(self.micDropMutedCount)")
                    }
                    return
                }
                self.micChunkCount += 1
                self.micPeakSum += result.peak
                if result.peak > self.micPeakMax { self.micPeakMax = result.peak }
                if !self.firstMicChunkLogged {
                    self.firstMicChunkLogged = true
                    print("[RealtimeVoice] first mic chunk sent — b64Len=\(result.base64.count), peak=\(String(format: "%.4f", result.peak))")
                } else if self.micChunkCount % 50 == 0 {
                    // 약 2~4초 주기 (hw sampleRate에 따라). peak 요약 후 누적 리셋.
                    let avg = self.micPeakSum / 50
                    print("[RealtimeVoice] mic chunks=\(self.micChunkCount) avgPeak=\(String(format: "%.4f", avg)) maxPeak=\(String(format: "%.4f", self.micPeakMax)) mutedDrops=\(self.micDropMutedCount) convFails=\(self.micConvertFailCount) echoDrops=\(self.echoDropCount)")
                    self.micPeakSum = 0
                    self.micPeakMax = 0
                }
                // AI 발화 중에는 마이크 입력을 OpenAI에 전혀 보내지 않음.
                // 스피커 루프백을 사용자 발화로 오인식하는 것을 근본 차단.
                // (barge-in은 포기 — 사용자는 AI 말이 끝난 후 발화. response.done 수신 시 isAssistantSpeaking=false로 전환)
                // 부수효과: 사용자 발화 초반이 잘리지 않아 whisper 언어 감지도 정확해짐.
                if self.isAssistantSpeaking {
                    self.echoDropCount += 1
                    return
                }
                await self.sendEvent([
                    "type": "input_audio_buffer.append",
                    "audio": result.base64
                ])
            }
        }

        print("[RealtimeVoice] installMicTap completed — bufferSize=\(bufferSize)")
    }

    // MARK: - Mic Capture → PCM16 Base64

    /// AVAudioPCMBuffer (하드웨어 Float32) → 24kHz Int16 mono → Base64 string.
    /// Audio render thread에서 호출되므로 순수 함수로 유지합니다.
    /// 반환값의 peak(0.0~1.0 근사)은 입력 buffer의 절대 진폭 최댓값 — 마이크가 실제 신호를 받고 있는지 진단용.
    nonisolated private static func convertToPCM16Base64(
        input: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> (base64: String, peak: Float)? {
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

        // 입력 buffer에서 peak 진폭 계산 (마이크 실신호 여부 진단용)
        var peak: Float = 0
        let inFrames = Int(input.frameLength)
        if input.format.commonFormat == .pcmFormatFloat32, let f32 = input.floatChannelData?[0] {
            for i in 0..<inFrames {
                let v = abs(f32[i])
                if v > peak { peak = v }
            }
        } else if input.format.commonFormat == .pcmFormatInt16, let i16 = input.int16ChannelData?[0] {
            for i in 0..<inFrames {
                let v = abs(Float(i16[i])) / 32768.0
                if v > peak { peak = v }
            }
        }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Ptr, count: byteCount)
        return (data.base64EncodedString(), peak)
    }

    // MARK: - Playback: Base64 PCM16 → AVAudioPCMBuffer

    private func enqueuePlaybackChunk(base64: String) {
        // barge-in으로 isAssistantSpeaking이 false면 이후 도착한 잔여 delta 무시
        guard isAssistantSpeaking else { return }
        guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }
        guard let sourceFmt = playbackSourceFormat,
              let outFmt = outputFormat,
              let converter = playbackConverter else {
            return
        }

        // 1) OpenAI 원본 데이터를 source buffer(24k int16 mono)에 적재
        let sourceFrames = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard sourceFrames > 0,
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFmt, frameCapacity: sourceFrames) else {
            return
        }
        sourceBuffer.frameLength = sourceFrames
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let dst = sourceBuffer.int16ChannelData?[0] else { return }
            memcpy(dst, src, Int(sourceFrames) * MemoryLayout<Int16>.size)
        }

        // 2) converter로 outputNode 포맷에 맞게 변환 (sampleRate + channelCount + Float32 변환 모두 자동)
        let ratio = outFmt.sampleRate / sourceFmt.sampleRate
        let outCapacity = AVAudioFrameCount(Double(sourceFrames) * ratio + 32)
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCapacity) else {
            return
        }

        var convError: NSError?
        var provided = false
        converter.convert(to: targetBuffer, error: &convError) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return sourceBuffer
        }

        guard convError == nil, targetBuffer.frameLength > 0 else {
            if let e = convError {
                print("[RealtimeVoice] playback convert failed: \(e.localizedDescription)")
            }
            return
        }

        if audioEngine.isRunning && playerNode.engine != nil {
            // `.dataPlayedBack` 콜백은 buffer가 실제 스피커에서 재생 완료된 시점에 호출.
            // 모든 buffer 재생이 끝났고 response.done이 이미 왔다면 그때 마이크 재개.
            pendingPlaybackFinishesExpected += 1
            playerNode.scheduleBuffer(targetBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePlaybackBufferFinished()
                }
            }
            scheduleBufferCount += 1
            if scheduleBufferCount == 1 {
                let pfmt = playerNode.outputFormat(forBus: 0)
                print("[RealtimeVoice] first scheduleBuffer — playerOut=\(pfmt.sampleRate)/\(pfmt.channelCount), targetFrames=\(targetBuffer.frameLength), playerVol=\(playerNode.volume), playerPlaying=\(playerNode.isPlaying), engineRunning=\(audioEngine.isRunning)")
            } else if scheduleBufferCount % 25 == 0 {
                print("[RealtimeVoice] scheduleBuffer count=\(scheduleBufferCount), pendingQueued=\(pendingQueuedCount)")
            }
        } else {
            pendingPlaybackBuffers.append(targetBuffer)
            pendingQueuedCount += 1
            if pendingQueuedCount == 1 || pendingQueuedCount % 25 == 0 {
                print("[RealtimeVoice] playback queued (engine not running yet) — pending=\(pendingPlaybackBuffers.count), engineRunning=\(audioEngine.isRunning), playerEngine=\(playerNode.engine != nil)")
            }
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
        // 남아있던 스케줄 카운트도 리셋 (stop으로 flush되므로 completion 일부가 호출되지 않을 수 있음)
        pendingPlaybackFinishesExpected = 0
        responseDoneAwaitingPlayback = false
        if audioEngine.isRunning {
            playerNode.play()
        }
    }

    /// 한 buffer 재생이 실제 스피커에서 완료됐을 때 호출.
    /// response.done이 이미 도달했고 남은 재생 버퍼가 0이면 마이크 재개 (echo 루프 차단 해제).
    private func handlePlaybackBufferFinished() {
        if pendingPlaybackFinishesExpected > 0 {
            pendingPlaybackFinishesExpected -= 1
        }
        if responseDoneAwaitingPlayback && pendingPlaybackFinishesExpected <= 0 {
            responseDoneAwaitingPlayback = false
            isAssistantSpeaking = false
            print("[RealtimeVoice] mic re-enabled (all playback finished, echoDrops=\(echoDropCount))")
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
            // 영어 학습 앱이므로 whisper 언어를 en으로 고정.
            // 자동 감지일 때 한국어/일본어로 오인식되는 회귀 방지.
            "input_audio_transcription": [
                "model": "whisper-1",
                "language": "en"
            ],
            "turn_detection": [
                "type": "server_vad",
                // float에서 정확히 표현되는 값만 사용 (0.3, 0.6 등은 17자리 확장됨).
                // 0.25 = 2^-2로 정확. 기본값 0.5보다 민감해 barge-in 감도 향상.
                "threshold": 0.25,
                "prefix_padding_ms": 300,
                // 자연스러운 말 사이 pause(생각 중) 허용. 500은 너무 짧아 사용자가 잠깐 쉬어도 턴이 끊김.
                "silence_duration_ms": 900,
                "create_response": true
            ],
            // 0.875 = 2^-1 + 2^-2 + 2^-3 — float에서 정확히 표현되는 값.
            // 기본 0.8보다 표현 다양성↑로 같은 시나리오라도 세션마다 대화 느낌 달라짐.
            "temperature": 0.875
        ]
        await sendEvent([
            "type": "session.update",
            "session": sessionConfig
        ])
    }

    private func sendEvent(_ dict: [String: Any]) async {
        guard let webSocket else {
            sendDropNoWSCount += 1
            if sendDropNoWSCount == 1 || sendDropNoWSCount % 100 == 0 {
                let t = dict["type"] as? String ?? "?"
                print("[RealtimeVoice] sendEvent dropped (no webSocket) count=\(sendDropNoWSCount) lastType=\(t)")
            }
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        do {
            try await webSocket.send(.string(str))
        } catch {
            let t = dict["type"] as? String ?? "?"
            print("[RealtimeVoice] send failed (type=\(t)): \(error.localizedDescription)")
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
            currentResponseId = nil
            // 서버가 응답 생성은 끝냈지만 iOS 스피커는 아직 스케줄된 buffer를 재생 중일 수 있음.
            // 남은 재생이 있으면 마지막 buffer의 .dataPlayedBack 콜백에서 마이크 재개.
            // 없으면 (즉시 완료) 여기서 바로 재개.
            if pendingPlaybackFinishesExpected > 0 {
                responseDoneAwaitingPlayback = true
                print("[RealtimeVoice] response.done — awaiting \(pendingPlaybackFinishesExpected) buffers to finish before mic re-enable")
            } else {
                isAssistantSpeaking = false
                print("[RealtimeVoice] response.done — mic re-enabled immediately (no pending playback)")
            }

        case "conversation.item.input_audio_transcription.completed":
            let rawText = obj["transcript"] as? String ?? ""
            print("[RealtimeVoice] user transcription completed: \"\(rawText)\" (deltaCount=\(userTranscriptDeltaCount))")
            let finalText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            partialUserText = ""
            if let entryId = pendingUserEntryId,
               let idx = transcript.firstIndex(where: { $0.id == entryId }) {
                if finalText.isEmpty {
                    // 무음/인식 실패 — placeholder 제거
                    transcript.remove(at: idx)
                } else {
                    transcript[idx].text = finalText
                    fetchTranslation(for: entryId, text: finalText)
                }
                pendingUserEntryId = nil
            } else if !finalText.isEmpty {
                // Fallback (committed 이벤트를 놓친 경우) — 새로 append
                let entry = TranscriptEntry(speaker: .user, text: finalText, createdAt: Date())
                transcript.append(entry)
                fetchTranslation(for: entry.id, text: finalText)
            }

        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String {
                userTranscriptDeltaCount += 1
                if userTranscriptDeltaCount == 1 {
                    print("[RealtimeVoice] first user transcription delta: \"\(delta)\"")
                }
                // pending placeholder entry에 점진적으로 텍스트 채워 넣기
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

        case "conversation.item.input_audio_transcription.failed":
            let errorDict = obj["error"] as? [String: Any]
            let message = errorDict?["message"] as? String ?? "unknown"
            print("[RealtimeVoice] user transcription FAILED: \(message)")

        case "input_audio_buffer.speech_started":
            speechStartedCount += 1
            let audioStartMs = obj["audio_start_ms"] as? Int ?? -1
            print("[RealtimeVoice] speech_started #\(speechStartedCount) — assistantSpeaking=\(isAssistantSpeaking), micChunks=\(micChunkCount), audioStartMs=\(audioStartMs)")
            // 사용자가 말하기 시작 → AI가 말 중이면 중단 (barge-in)
            if isAssistantSpeaking {
                isAssistantSpeaking = false  // 즉시 false로 → 이후 delta drop + 중복 cancel 방지
                cancelPlayback()
                await sendEvent(["type": "response.cancel"])
            }

        case "input_audio_buffer.speech_stopped":
            speechStoppedCount += 1
            let audioEndMs = obj["audio_end_ms"] as? Int ?? -1
            print("[RealtimeVoice] speech_stopped #\(speechStoppedCount) — audioEndMs=\(audioEndMs)")

        case "input_audio_buffer.committed":
            audioCommittedCount += 1
            let itemId = obj["item_id"] as? String ?? "?"
            print("[RealtimeVoice] audio committed #\(audioCommittedCount) — itemId=\(itemId)")
            // User 말풍선을 AI 응답보다 먼저 UI에 노출하기 위한 placeholder entry.
            // committed 이벤트가 response.created보다 먼저 도착하므로 여기서 append하면 순서 보장.
            // transcription.delta/completed 이벤트에서 이 entry의 text를 업데이트.
            let placeholder = TranscriptEntry(speaker: .user, text: "…", createdAt: Date())
            transcript.append(placeholder)
            pendingUserEntryId = placeholder.id
            partialUserText = ""
            userTranscriptDeltaCount = 0

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
