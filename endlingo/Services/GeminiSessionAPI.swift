import Foundation

/// Gemini Live API용 세션 등록 + quota 검증을 Supabase Edge Function에서 처리합니다.
///
/// OpenAI와 달리 ephemeral key가 불필요 (Firebase SDK가 인증 처리).
/// quota 관리 + session_id 발급만 수행합니다.
enum GeminiSessionAPI {

    struct SessionResponse: Decodable {
        let provider: String?
        let tier: String?
        let maxDurationSeconds: Int?
        let remainingSecondsToday: Int?
        let sessionId: UUID?

        enum CodingKeys: String, CodingKey {
            case provider
            case tier
            case maxDurationSeconds = "max_duration_seconds"
            case remainingSecondsToday = "remaining_seconds_today"
            case sessionId = "session_id"
        }
    }

    /// Edge Function `gemini-session`을 호출해 quota를 확인하고 session_id를 받습니다.
    static func registerSession(scenario: PhoneCallScenario, personaNameOverride: String? = nil) async throws -> SessionResponse {
        let auth = AuthService.shared
        guard let token = await auth.accessToken else {
            throw RealtimeSessionAPI.Error.notLoggedIn
        }

        guard let url = URL(string: "\(SupabaseConfig.functionsBaseURL)/gemini-session") else {
            throw RealtimeSessionAPI.Error.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "scenario_id": scenario.id,
            "scenario_title": scenario.title,
            "persona_name": personaNameOverride ?? scenario.personaName,
            "persona_emoji": scenario.emoji,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        print("[GeminiSessionAPI] calling \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RealtimeSessionAPI.Error.malformedResponse
        }
        let bodyPreview = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
        print("[GeminiSessionAPI] http \(http.statusCode): \(bodyPreview)")

        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(SessionResponse.self, from: data)
        case 401:
            throw RealtimeSessionAPI.Error.notLoggedIn
        case 429:
            // call_in_progress vs daily_limit_reached 구분
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorCode = obj["error"] as? String, errorCode == "call_in_progress" {
                throw RealtimeSessionAPI.Error.httpStatus(429, "이미 진행 중인 통화가 있습니다")
            }
            let info = parseDailyLimitInfo(data)
            throw RealtimeSessionAPI.Error.dailyLimitReached(info)
        case 503:
            throw RealtimeSessionAPI.Error.serverUnavailable
        default:
            let body = String(data: data, encoding: .utf8)
            throw RealtimeSessionAPI.Error.httpStatus(http.statusCode, body)
        }
    }

    private static func parseDailyLimitInfo(_ data: Data) -> RealtimeSessionAPI.DailyLimitInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limit = obj["daily_limit_seconds"] as? Int,
              let used = obj["used_seconds"] as? Int else {
            return nil
        }
        return RealtimeSessionAPI.DailyLimitInfo(limit: limit, used: used)
    }
}
