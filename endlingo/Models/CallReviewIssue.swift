import Foundation

/// 통화 종료 후 AI가 생성한 영작 피드백의 단일 항목.
/// `phone_call_sessions.review_issues` JSONB 배열의 원소로 저장되며,
/// `PhoneCallAIService.review()` 응답 및 `PhoneCallDetailView` 표시에도 재사용됩니다.
struct CallReviewIssue: Codable, Identifiable, Hashable, Sendable {
    let original: String
    let improved: String
    let explanation: String

    var id: String { original + "→" + improved }
}
