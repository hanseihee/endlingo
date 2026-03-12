import Foundation

struct LearningRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID?
    let date: String
    let level: String
    let environment: String
    let xpEarned: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date, level, environment
        case userId = "user_id"
        case xpEarned = "xp_earned"
        case createdAt = "created_at"
    }
}
