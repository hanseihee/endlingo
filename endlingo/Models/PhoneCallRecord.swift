import Foundation

/// AI 전화영어 통화 기록. 로컬 파일(Documents)과 Supabase `phone_call_sessions` 테이블에 동기화됩니다.
struct PhoneCallRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID?
    let scenarioId: String
    let scenarioTitle: String
    let personaName: String
    let personaEmoji: String
    var durationSeconds: Int
    var transcript: [TranscriptLine]
    let startedAt: Date
    let createdAt: Date
    var reviewIssues: [CallReviewIssue]?

    struct TranscriptLine: Codable, Hashable, Sendable {
        let speaker: String  // "user" | "assistant"
        let text: String
        var translation: String?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case scenarioId = "scenario_id"
        case scenarioTitle = "scenario_title"
        case personaName = "persona_name"
        case personaEmoji = "persona_emoji"
        case durationSeconds = "duration_seconds"
        case transcript
        case startedAt = "started_at"
        case createdAt = "created_at"
        case reviewIssues = "review_issues"
    }
}
