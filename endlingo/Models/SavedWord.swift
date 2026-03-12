import Foundation

struct SavedWord: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID?
    let word: String
    let sentence: String
    let lessonDate: String
    let savedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, word, sentence
        case userId = "user_id"
        case lessonDate = "lesson_date"
        case savedAt = "saved_at"
    }
}
