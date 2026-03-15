import Foundation

struct SavedGrammar: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID?
    let pattern: String
    let explanation: String
    let example: String?
    let sentence: String
    let lessonDate: String
    let savedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, pattern, explanation, example, sentence
        case userId = "user_id"
        case lessonDate = "lesson_date"
        case savedAt = "saved_at"
    }
}
