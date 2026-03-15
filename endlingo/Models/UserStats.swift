import Foundation

struct UserStats: Codable, Equatable {
    var totalXP: Int = 0
    var userLevel: Int = 1
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var totalLearningDays: Int = 0
    var totalQuizzes: Int = 0
    var correctQuizzes: Int = 0

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
