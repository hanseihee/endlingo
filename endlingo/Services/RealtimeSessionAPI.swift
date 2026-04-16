import Foundation

/// OpenAI Realtime API용 ephemeral key를 Supabase Edge Function에서 발급받습니다.
///
/// 실제 OpenAI API key는 Edge Function 환경변수(`OPENAI_API_KEY`)에만 저장되고,
/// iOS 앱은 단기 만료되는 ephemeral secret만 사용합니다.
///
/// 인증: 로그인한 사용자의 JWT가 필요합니다 (`AuthService.accessToken`).
/// 비로그인 시 `Error.notLoggedIn`이 throw 되어 호출부에서 로그인 안내 UI로 분기합니다.
enum RealtimeSessionAPI {

    struct EphemeralKeyResponse: Decodable {
        let ephemeralKey: String
        let expiresAt: Int?
        let model: String?
        let tier: String?
        let maxDurationSeconds: Int?
        let remainingSecondsToday: Int?
        let sessionId: UUID?

        enum CodingKeys: String, CodingKey {
            case ephemeralKey = "ephemeral_key"
            case expiresAt = "expires_at"
            case model
            case tier
            case maxDurationSeconds = "max_duration_seconds"
            case remainingSecondsToday = "remaining_seconds_today"
            case sessionId = "session_id"
        }
    }

    struct DailyLimitInfo {
        let limit: Int
        let used: Int
    }

    enum Error: Swift.Error, LocalizedError {
        case badURL
        case notLoggedIn
        case dailyLimitReached(DailyLimitInfo?)
        case serverUnavailable
        case httpStatus(Int, String?)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .badURL: return "bad URL"
            case .notLoggedIn: return String(localized: "AI 전화영어는 로그인 후 이용할 수 있어요")
            case .dailyLimitReached(let info):
                if let info {
                    return String(localized: "오늘 사용 가능한 통화 횟수를 모두 사용했어요 (\(info.used)/\(info.limit))")
                }
                return String(localized: "오늘 사용 가능한 통화 횟수를 모두 사용했어요")
            case .serverUnavailable: return String(localized: "일시적으로 서버에 연결할 수 없어요")
            case .httpStatus(let code, let body): return "HTTP \(code): \(body ?? "no body")"
            case .malformedResponse: return "malformed response"
            }
        }
    }

    /// Edge Function `realtime-session`을 호출해 ephemeral key + 서버 session_id를 받습니다.
    /// 로그인 필수. 일일 한도 초과 시 `dailyLimitReached` throw.
    /// 서버가 pending row를 미리 insert해 quota를 정확히 차감하고, session_id를 반환.
    static func fetchEphemeralKey(scenario: PhoneCallScenario, personaNameOverride: String? = nil) async throws -> EphemeralKeyResponse {
        let auth = AuthService.shared
        guard let token = await auth.accessToken else {
            print("[RealtimeSessionAPI] accessToken is nil — isLoggedIn=\(auth.isLoggedIn), userId=\(auth.userId?.uuidString ?? "nil"), email=\(auth.userEmail ?? "nil")")
            throw Error.notLoggedIn
        }
        print("[RealtimeSessionAPI] token acquired (len=\(token.count)), calling edge function")

        guard let url = URL(string: "\(SupabaseConfig.functionsBaseURL)/realtime-session") else {
            throw Error.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "voice": scenario.voice,
            "scenario_id": scenario.id,
            "scenario_title": scenario.title,
            "persona_name": personaNameOverride ?? scenario.personaName,
            "persona_emoji": scenario.emoji,
            "tier": SubscriptionService.shared.currentTier.rawValue,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error.malformedResponse
        }
        let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
        print("[RealtimeSessionAPI] http \(http.statusCode): \(bodyPreview)")

        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(EphemeralKeyResponse.self, from: data)
        case 401:
            throw Error.notLoggedIn
        case 429:
            let info = parseDailyLimitInfo(data)
            throw Error.dailyLimitReached(info)
        case 503:
            throw Error.serverUnavailable
        default:
            let body = String(data: data, encoding: .utf8)
            throw Error.httpStatus(http.statusCode, body)
        }
    }

    private static func parseDailyLimitInfo(_ data: Data) -> DailyLimitInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limit = obj["limit"] as? Int,
              let used = obj["used"] as? Int else {
            return nil
        }
        return DailyLimitInfo(limit: limit, used: used)
    }
}
