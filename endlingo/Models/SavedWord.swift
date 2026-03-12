import Foundation

struct SavedWord: Codable, Identifiable, Equatable {
    let id: UUID
    let word: String
    let sentence: String
    let lessonDate: String
    let savedAt: Date

    // Supabase 연동 시 추가:
    // let userId: String

    enum CodingKeys: String, CodingKey {
        case id, word, sentence
        case lessonDate = "lesson_date"
        case savedAt = "saved_at"
    }
}
