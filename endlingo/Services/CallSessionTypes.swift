import Foundation

/// AI 전화영어 세션 공통 에러 타입.
/// Edge Function(`gemini-session` 등) 호출 시 발생 가능한 상태를 통합.
enum CallSessionError: Swift.Error, LocalizedError {
    case badURL
    case notLoggedIn
    case dailyLimitReached(CallDailyLimitInfo?)
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

/// 일일 통화 한도 응답.
struct CallDailyLimitInfo {
    let limit: Int
    let used: Int
}
