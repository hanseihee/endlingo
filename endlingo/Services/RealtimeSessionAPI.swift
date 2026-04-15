import Foundation

/// OpenAI Realtime API용 ephemeral key를 Supabase Edge Function에서 발급받습니다.
///
/// 실제 OpenAI API key는 Edge Function 환경변수(`OPENAI_API_KEY`)에만 저장되고,
/// iOS 앱은 단기 만료되는 ephemeral secret만 사용합니다.
enum RealtimeSessionAPI {

    struct EphemeralKeyResponse: Decodable {
        let ephemeralKey: String
        let expiresAt: Int?
        let model: String?

        enum CodingKeys: String, CodingKey {
            case ephemeralKey = "ephemeral_key"
            case expiresAt = "expires_at"
            case model
        }
    }

    enum Error: Swift.Error, LocalizedError {
        case badURL
        case httpStatus(Int, String?)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .badURL: return "bad URL"
            case .httpStatus(let code, let body): return "HTTP \(code): \(body ?? "no body")"
            case .malformedResponse: return "malformed response"
            }
        }
    }

    /// Edge Function `realtime-session`을 호출해 ephemeral key를 받습니다.
    static func fetchEphemeralKey(voice: String) async throws -> String {
        guard let url = URL(string: "\(SupabaseConfig.functionsBaseURL)/realtime-session") else {
            throw Error.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["voice": voice])
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw Error.httpStatus(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(EphemeralKeyResponse.self, from: data)
        return decoded.ephemeralKey
    }
}
