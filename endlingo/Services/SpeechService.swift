import AVFoundation
import SwiftUI

@Observable
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private(set) var speakingId: String?
    private let synthesizer = AVSpeechSynthesizer()

    private var accent: String {
        UserDefaults.standard.string(forKey: "pronunciationAccent") ?? "en-US"
    }

    private init() {}

    /// 텍스트를 읽어줍니다. id로 현재 재생 중인 항목을 식별합니다.
    func speak(_ text: String, id: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            if speakingId == id {
                speakingId = nil
                return
            }
        }

        // 오디오 세션을 재생 모드로 설정 (녹음 후 TTS 안 되는 문제 방지)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: accent)
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.1

        speakingId = id
        synthesizer.speak(utterance)

        Task {
            while synthesizer.isSpeaking {
                try? await Task.sleep(for: .milliseconds(200))
            }
            if speakingId == id {
                speakingId = nil
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingId = nil
    }

    func isSpeaking(id: String) -> Bool {
        speakingId == id
    }
}
