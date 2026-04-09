import Foundation

struct UserStats: Codable, Equatable {
    var totalXP: Int = 0
    var userLevel: Int = 1
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var totalLearningDays: Int = 0
    var totalQuizzes: Int = 0
    var correctQuizzes: Int = 0
    var pronunciationCount: Int = 0
    var pronunciationCorrect: Int = 0
    var sentenceArrangeCount: Int = 0
    var sentenceArrangeCorrect: Int = 0

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalXP = try container.decodeIfPresent(Int.self, forKey: .totalXP) ?? 0
        userLevel = try container.decodeIfPresent(Int.self, forKey: .userLevel) ?? 1
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak = try container.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        totalLearningDays = try container.decodeIfPresent(Int.self, forKey: .totalLearningDays) ?? 0
        totalQuizzes = try container.decodeIfPresent(Int.self, forKey: .totalQuizzes) ?? 0
        correctQuizzes = try container.decodeIfPresent(Int.self, forKey: .correctQuizzes) ?? 0
        pronunciationCount = try container.decodeIfPresent(Int.self, forKey: .pronunciationCount) ?? 0
        pronunciationCorrect = try container.decodeIfPresent(Int.self, forKey: .pronunciationCorrect) ?? 0
        sentenceArrangeCount = try container.decodeIfPresent(Int.self, forKey: .sentenceArrangeCount) ?? 0
        sentenceArrangeCorrect = try container.decodeIfPresent(Int.self, forKey: .sentenceArrangeCorrect) ?? 0
    }

    var quizAccuracy: Double {
        totalQuizzes > 0 ? Double(correctQuizzes) / Double(totalQuizzes) * 100.0 : 0
    }

    var xpForCurrentLevel: Int { (userLevel - 1) * 100 }
    var xpForNextLevel: Int { userLevel * 100 }

    var xpProgress: Double {
        let needed = xpForNextLevel - xpForCurrentLevel
        let progress = totalXP - xpForCurrentLevel
        return needed > 0 ? min(Double(progress) / Double(needed), 1.0) : 1.0
    }

    var levelTitle: String {
        switch userLevel {
        case 1...5: return String(localized: "초보 학습자")
        case 6...10: return String(localized: "열정 학습자")
        case 11...20: return String(localized: "숙련 학습자")
        case 21...50: return String(localized: "영어 달인")
        default: return String(localized: "마스터")
        }
    }

    mutating func recalculateLevel() {
        userLevel = max(1, totalXP / 100 + 1)
    }
}
