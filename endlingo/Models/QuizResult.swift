import Foundation

struct QuizResult: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID?
    let date: String
    let quizType: String
    let wordId: UUID
    let word: String
    let isCorrect: Bool
    let xpEarned: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date, word
        case userId = "user_id"
        case quizType = "quiz_type"
        case wordId = "word_id"
        case isCorrect = "is_correct"
        case xpEarned = "xp_earned"
        case createdAt = "created_at"
    }
}
