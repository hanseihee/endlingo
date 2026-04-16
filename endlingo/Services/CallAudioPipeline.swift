@preconcurrency import AVFoundation
import Foundation

/// OpenAI / Gemini 공통 오디오 엔진 파이프라인.
///
/// 책임:
/// - AVAudioEngine + VPIO 구성 및 수명 주기 관리
/// - 마이크 캡처 → PCM16 LE mono 변환 → 콜백 전달
/// - 서버 오디오(PCM16 LE mono) → outputNode 포맷 변환 → playerNode 재생
/// - 스피커/수화기 경로 전환
///
/// 비책임:
/// - AVAudioSession 카테고리/활성화 (CallKit이 소유)
/// - 네트워크 통신 (RealtimeProviderAdapter가 소유)
@MainActor
final class CallAudioPipeline {

    // MARK: - Types

    /// 마이크에서 캡처된 PCM16 데이터를 전달하는 콜백.
    /// Data는 little-endian Int16 mono, sampleRate는 생성 시 지정한 inputSampleRate.
    typealias MicOutputHandler = @Sendable (Data) async -> Void

    // MARK: - State

    private(set) var isSpeakerOn: Bool = true
    /// AI 발화 중 echo 방지를 위해 마이크 입력을 drop할지 여부. 외부(VoiceService)에서 제어.
    var isEchoSuppressed: Bool = false
    /// 마이크 음소거 상태. 외부(VoiceService)에서 제어.
    var isMuted: Bool = false

    // MARK: - Config

    /// 마이크 캡처 목표 샘플레이트 (OpenAI: 24000, Gemini: 16000).
    private let inputSampleRate: Double
    /// 서버 오디오 수신 샘플레이트 (공통: 24000).
    private let outputSampleRate: Double

    // MARK: - Audio Engine

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var micConverter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var isEngineConfigured = false
    private var pendingPlaybackBuffers: [AVAudioPCMBuffer] = []
    private var playbackSourceFormat: AVAudioFormat?
    private var playbackConverter: AVAudioConverter?
    private var micOutputHandler: MicOutputHandler?
    private var configChangeObserver: NSObjectProtocol?

    // MARK: - Playback Tracking

    /// 현재 스케줄된 재생 버퍼 중 아직 완료되지 않은 수.
    private(set) var pendingPlaybackCount: Int = 0
    /// response.done 이후 재생 완료 대기 상태.
    var isAwaitingPlaybackFinish: Bool = false
    /// 모든 재생 완료 시 호출되는 콜백.
    var onAllPlaybackFinished: (() -> Void)?
    /// 오디오 엔진 시작 실패 시 호출되는 콜백. 에러 메시지 전달.
    var onStartFailed: ((String) -> Void)?

    // MARK: - Diagnostics

    private var micChunkCount: Int = 0
    private var micDropMutedCount: Int = 0
    private var micConvertFailCount: Int = 0
    private var micPeakSum: Float = 0
    private var micPeakMax: Float = 0
    private var echoDropCount: Int = 0
    private var scheduleBufferCount: Int = 0
    private var pendingQueuedCount: Int = 0

    // MARK: - Init

    init(inputSampleRate: Double, outputSampleRate: Double) {
        self.inputSampleRate = inputSampleRate
        self.outputSampleRate = outputSampleRate
    }

    // MARK: - Public API

    /// 오디오 엔진을 구성하고 시작합니다.
    /// CallKit `didActivate` 이후에 호출하세요.
    func start(onMicOutput: @escaping MicOutputHandler) {
        micOutputHandler = onMicOutput
        configureEngineIfNeeded()
        installMicTap()
        audioEngine.prepare()

        do {
            if !audioEngine.isRunning { try audioEngine.start() }
            if !playerNode.isPlaying { playerNode.play() }
            flushPendingPlayback()
            applySpeakerRoute()
            let input = audioEngine.inputNode
            let output = audioEngine.outputNode
            print("[AudioPipeline] started — running=\(audioEngine.isRunning), player=\(playerNode.isPlaying), vpio=\(input.isVoiceProcessingEnabled), micSR=\(input.outputFormat(forBus: 0).sampleRate), outSR=\(output.inputFormat(forBus: 0).sampleRate), speaker=\(isSpeakerOn)")
            if !audioEngine.isRunning {
                print("[AudioPipeline] WARNING silent-fail, retrying…")
                try? audioEngine.start()
                if !playerNode.isPlaying { playerNode.play() }
            }
        } catch {
            print("[AudioPipeline] start failed: \(error.localizedDescription)")
            onStartFailed?("audio engine start failed: \(error.localizedDescription)")
        }
    }

    /// 오디오 엔진을 정지합니다.
    func stop() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            playerNode.stop()
            audioEngine.stop()
        }
    }

    /// 전체 리소스 해제. 다음 통화에서 재구성합니다.
    func teardown() {
        stop()
        // Bug fix: NotificationCenter observer 해제 (메모리 누수 방지)
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        pendingPlaybackBuffers.removeAll()
        isEngineConfigured = false
        playbackConverter = nil
        playbackSourceFormat = nil
        micOutputHandler = nil
        pendingPlaybackCount = 0
        isAwaitingPlaybackFinish = false
        resetDiagnostics()
    }

    /// 스피커폰 ↔ 수화기 전환.
    func setSpeakerEnabled(_ enabled: Bool) {
        isSpeakerOn = enabled
        applySpeakerRoute()
    }

    // MARK: - Playback

    /// 서버에서 수신한 PCM16 오디오 base64를 디코딩하고 재생 큐에 추가합니다.
    func enqueuePlayback(base64PCM16: String) {
        guard let data = Data(base64Encoded: base64PCM16), !data.isEmpty else { return }
        guard let sourceFmt = playbackSourceFormat,
              let outFmt = outputFormat,
              let converter = playbackConverter else { return }

        let sourceFrames = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard sourceFrames > 0,
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFmt, frameCapacity: sourceFrames) else { return }
        sourceBuffer.frameLength = sourceFrames
        data.withUnsafeBytes { raw in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let dst = sourceBuffer.int16ChannelData?[0] else { return }
            memcpy(dst, src, Int(sourceFrames) * MemoryLayout<Int16>.size)
        }

        let ratio = outFmt.sampleRate / sourceFmt.sampleRate
        let outCapacity = AVAudioFrameCount(Double(sourceFrames) * ratio + 32)
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCapacity) else { return }

        var convError: NSError?
        var provided = false
        converter.convert(to: targetBuffer, error: &convError) { _, status in
            if provided { status.pointee = .noDataNow; return nil }
            provided = true
            status.pointee = .haveData
            return sourceBuffer
        }
        guard convError == nil, targetBuffer.frameLength > 0 else { return }

        if audioEngine.isRunning && playerNode.engine != nil {
            pendingPlaybackCount += 1
            playerNode.scheduleBuffer(targetBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePlaybackBufferFinished()
                }
            }
            scheduleBufferCount += 1
        } else {
            pendingPlaybackBuffers.append(targetBuffer)
            pendingQueuedCount += 1
        }
    }

    /// 재생 중인 모든 버퍼를 취소합니다 (barge-in).
    func cancelPlayback() {
        playerNode.stop()
        pendingPlaybackBuffers.removeAll()
        pendingPlaybackCount = 0
        isAwaitingPlaybackFinish = false
        if audioEngine.isRunning { playerNode.play() }
    }

    // MARK: - Private: Engine Config

    private func configureEngineIfNeeded() {
        guard !isEngineConfigured else { return }

        do {
            try audioEngine.inputNode.setVoiceProcessingEnabled(true)
            audioEngine.inputNode.isVoiceProcessingAGCEnabled = false
        } catch {
            print("[AudioPipeline] VPIO failed: \(error.localizedDescription)")
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: true
        ) else { return }
        playbackSourceFormat = sourceFormat

        let outFmt = audioEngine.outputNode.inputFormat(forBus: 0)
        outputFormat = outFmt

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.outputNode, format: outFmt)
        playerNode.volume = 1.0

        playbackConverter = AVAudioConverter(from: sourceFormat, to: outFmt)
        isEngineConfigured = true

        // 엔진 구성 변경 감지 (observer 토큰 저장 → teardown에서 해제)
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.audioEngine.isRunning else { return }
                do {
                    try self.audioEngine.start()
                    if !self.playerNode.isPlaying { self.playerNode.play() }
                } catch {
                    print("[AudioPipeline] auto-restart failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func installMicTap() {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else { return }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: true
        ) else { return }

        micConverter = AVAudioConverter(from: hwFormat, to: targetFormat)
        guard let converter = micConverter else { return }

        let bufferSize: AVAudioFrameCount = 2048
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            guard let result = Self.convertToPCM16Data(input: buffer, converter: converter, targetFormat: targetFormat) else {
                Task { @MainActor [weak self] in self?.micConvertFailCount += 1 }
                return
            }
            Task { @MainActor [weak self] in
                guard let self, let handler = self.micOutputHandler else { return }
                if self.isMuted { self.micDropMutedCount += 1; return }
                if self.isEchoSuppressed { self.echoDropCount += 1; return }
                self.micChunkCount += 1
                self.micPeakSum += result.peak
                if result.peak > self.micPeakMax { self.micPeakMax = result.peak }
                if self.micChunkCount % 50 == 0 {
                    let avg = self.micPeakSum / 50
                    print("[AudioPipeline] mic #\(self.micChunkCount) avgPeak=\(String(format: "%.4f", avg)) mutedDrops=\(self.micDropMutedCount) echoDrops=\(self.echoDropCount)")
                    self.micPeakSum = 0; self.micPeakMax = 0
                }
                await handler(result.data)
            }
        }
    }

    // MARK: - Private: PCM16 Conversion (nonisolated)

    nonisolated private static func convertToPCM16Data(
        input: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> (data: Data, peak: Float)? {
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 16)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return nil }

        var error: NSError?
        var provided = false
        converter.convert(to: outBuffer, error: &error) { _, status in
            if provided { status.pointee = .noDataNow; return nil }
            provided = true
            status.pointee = .haveData
            return input
        }
        guard error == nil,
              let int16Ptr = outBuffer.int16ChannelData?[0],
              outBuffer.frameLength > 0 else { return nil }

        var peak: Float = 0
        if input.format.commonFormat == .pcmFormatFloat32, let f32 = input.floatChannelData?[0] {
            for i in 0..<Int(input.frameLength) {
                let v = abs(f32[i]); if v > peak { peak = v }
            }
        }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Ptr, count: byteCount)
        return (data, peak)
    }

    // MARK: - Private: Playback Helpers

    private func flushPendingPlayback() {
        guard !pendingPlaybackBuffers.isEmpty, audioEngine.isRunning else { return }
        for buffer in pendingPlaybackBuffers {
            pendingPlaybackCount += 1
            playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handlePlaybackBufferFinished() }
            }
        }
        pendingPlaybackBuffers.removeAll()
    }

    private func handlePlaybackBufferFinished() {
        if pendingPlaybackCount > 0 { pendingPlaybackCount -= 1 }
        if isAwaitingPlaybackFinish && pendingPlaybackCount <= 0 {
            isAwaitingPlaybackFinish = false
            onAllPlaybackFinished?()
        }
    }

    private func applySpeakerRoute() {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        } catch {
            print("[AudioPipeline] route override failed: \(error.localizedDescription)")
        }
    }

    private func resetDiagnostics() {
        micChunkCount = 0; micDropMutedCount = 0; micConvertFailCount = 0
        micPeakSum = 0; micPeakMax = 0; echoDropCount = 0
        scheduleBufferCount = 0; pendingQueuedCount = 0
    }
}
