import Foundation

/// 전화영어 보조 AI 호출: 실시간 번역 + 통화 후 리뷰.
/// 두 Edge Function(`translate-phone-turn`, `review-phone-call`)의 래퍼.
enum PhoneCallAIService {

    typealias CallIssue = CallReviewIssue

    // MARK: - Public API

    /// 단일 발화를 네이티브 언어로 번역합니다. 실패 시 nil 반환 (UI가 번역 생략).
    /// `provider`는 호출자(통화 스코프)가 캡처한 값 — 통화 간 race 방지.
    /// 생략 시 현재 MainActor의 PhoneCallController.currentProvider를 사용.
    static func translate(text: String, provider: CallAIProvider? = nil) async -> String? {
        let providerStr = await resolveProvider(provider)
        let body: [String: Any] = [
            "text": text,
            "native_language": currentNativeLanguage(),
            "provider": providerStr,
        ]
        do {
            let response: TranslationResponse = try await callFunction("translate-phone-turn", body: body)
            let trimmed = response.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            print("[PhoneCallAI] translate failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// 통화 종료 후 사용자 발화에 대한 교정 피드백을 가져옵니다.
    static func review(
        transcript: [PhoneCallRecord.TranscriptLine],
        level: String,
        provider: CallAIProvider? = nil
    ) async -> [CallIssue] {
        let transcriptJson = transcript.map { ["speaker": $0.speaker, "text": $0.text] }
        let providerStr = await resolveProvider(provider)
        let body: [String: Any] = [
            "transcript": transcriptJson,
            "native_language": currentNativeLanguage(),
            "level": level,
            "provider": providerStr,
        ]
        do {
            let response: ReviewResponse = try await callFunction("review-phone-call", body: body)
            return response.issues
        } catch {
            print("[PhoneCallAI] review failed: \(error.localizedDescription)")
            return []
        }
    }

    /// 명시적 provider가 있으면 그걸 쓰고, 없으면 현재 컨트롤러의 값을 조회.
    private static func resolveProvider(_ explicit: CallAIProvider?) async -> String {
        let provider: CallAIProvider
        if let explicit {
            provider = explicit
        } else {
            provider = await MainActor.run { PhoneCallController.shared.currentProvider }
        }
        switch provider {
        case .openAI: return "openai"
        case .gemini: return "gemini"
        }
    }

    // MARK: - Private

    private struct TranslationResponse: Decodable {
        let translation: String
    }

    private struct ReviewResponse: Decodable {
        let issues: [CallIssue]
    }

    private static func currentNativeLanguage() -> String {
        switch Locale.current.language.languageCode?.identifier {
        case "ja": return "ja"
        case "vi": return "vi"
        case "en": return "en"
        default: return "ko"
        }
    }

    private static func callFunction<T: Decodable>(
        _ path: String,
        body: [String: Any]
    ) async throws -> T {
        guard let token = await AuthService.shared.accessToken else {
            throw NSError(domain: "PhoneCallAI", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "not logged in"])
        }
        guard let url = URL(string: "\(SupabaseConfig.functionsBaseURL)/\(path)") else {
            throw NSError(domain: "PhoneCallAI", code: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "PhoneCallAI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
