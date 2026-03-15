import Speech
import AVFoundation
import SwiftUI

@Observable
@MainActor
final class SpeechRecognitionService {
    static let shared = SpeechRecognitionService()

    enum State: Equatable {
        case idle
        case recording
        case processing
        case completed
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recording, .recording),
                 (.processing, .processing), (.completed, .completed):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var liveTranscription = ""
    private(set) var result: PronunciationResult?
    private(set) var isPlayingRecording = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var referenceText = ""

    /// partial result 중 가장 긴 텍스트를 보존
    private var bestTranscription = ""

    // 녹음 파일 저장/재생
    private var recordingFileURL: URL?
    private var audioFile: AVAudioFile?
    private var audioPlayer: AVAudioPlayer?

    private init() {}

    // MARK: - Permissions

    var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }

        let micOK = await AVAudioApplication.requestRecordPermission()
        return micOK
    }

    // MARK: - Recording

    func startRecording(referenceText: String) async {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error(String(localized: "음성 인식을 사용할 수 없습니다"))
            return
        }

        let permitted = await requestPermissions()
        guard permitted else {
            state = .error(String(localized: "마이크와 음성 인식 권한이 필요합니다.\n설정 앱에서 권한을 허용해주세요."))
            return
        }

        cleanupAudio()

        self.referenceText = referenceText
        liveTranscription = ""
        bestTranscription = ""
        result = nil
        state = .recording

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // on-device 강제하지 않음 - 시스템이 최적 경로 선택
        recognitionRequest = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            // 녹음 파일 생성
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pronunciation_\(UUID().uuidString).caf")
            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            recordingFileURL = fileURL
            audioFile = file

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
                try? file.write(from: buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] taskResult, error in
                Task { @MainActor in
                    guard let self else { return }
                    // 이미 완료됐으면 무시
                    guard self.state == .recording || self.state == .processing else { return }

                    if let taskResult {
                        let text = taskResult.bestTranscription.formattedString
                        self.liveTranscription = text

                        // 가장 긴(좋은) 인식 결과 보존
                        if text.count > self.bestTranscription.count {
                            self.bestTranscription = text
                        }

                        if taskResult.isFinal {
                            self.finishWithResult()
                        }
                    }

                    if error != nil {
                        if self.state == .recording {
                            if self.bestTranscription.isEmpty {
                                self.state = .error(String(localized: "음성을 인식하지 못했습니다.\n다시 시도해주세요."))
                                self.cleanupAudio()
                            } else {
                                self.finishWithResult()
                            }
                        } else if self.state == .processing {
                            // stopRecording 후 에러 → 가지고 있는 텍스트로 완료
                            self.finishWithResult()
                        }
                    }
                }
            }
        } catch {
            state = .error(String(localized: "녹음을 시작할 수 없습니다"))
            cleanupAudio()
        }
    }

    func stopRecording() {
        guard state == .recording else { return }

        recognitionRequest?.endAudio()
        audioFile = nil

        if bestTranscription.isEmpty {
            state = .error(String(localized: "음성을 인식하지 못했습니다.\n다시 시도해주세요."))
            cleanupAudio()
        } else {
            state = .processing
            // isFinal 콜백 대기, 2초 타임아웃
            Task {
                try? await Task.sleep(for: .seconds(2.0))
                if state == .processing {
                    finishWithResult()
                }
            }
        }
    }

    // MARK: - Playback

    func playRecording() {
        guard let url = recordingFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }

        stopPlayback()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            isPlayingRecording = true
            player.play()

            Task {
                while player.isPlaying {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                isPlayingRecording = false
            }
        } catch {
            isPlayingRecording = false
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingRecording = false
    }

    // MARK: - Reset

    func reset() {
        stopPlayback()
        cleanupAudio()
        if let url = recordingFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingFileURL = nil
        state = .idle
        liveTranscription = ""
        bestTranscription = ""
        result = nil
        referenceText = ""
    }

    // MARK: - Private

    private func finishWithResult() {
        guard state == .recording || state == .processing else { return }

        audioFile = nil

        // 최종 인식 결과: bestTranscription (가장 긴 것) 우선 사용
        let finalText = bestTranscription.isEmpty ? liveTranscription : bestTranscription
        liveTranscription = finalText

        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error(String(localized: "음성을 인식하지 못했습니다.\n다시 시도해주세요."))
            cleanupRecognition()
            return
        }

        let scored = PronunciationScorer.score(
            reference: referenceText,
            spoken: finalText
        )
        result = scored
        state = .completed
        cleanupRecognition()
    }

    private func cleanupRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanupAudio() {
        cleanupRecognition()
        audioFile = nil
    }
}
