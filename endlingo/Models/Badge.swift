import Foundation

enum BadgeType: String, Codable, CaseIterable, Identifiable {
    case firstStep = "first_step"
    case wordCollector50 = "word_collector_50"
    case wordCollector100 = "word_collector_100"
    case sevenDayStreak = "seven_day_streak"
    case thirtyDayStreak = "thirty_day_streak"
    case quizMaster = "quiz_master"
    case quizEnthusiast = "quiz_enthusiast"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstStep: return "첫 걸음"
        case .wordCollector50: return "단어 수집가"
        case .wordCollector100: return "단어 100개"
        case .sevenDayStreak: return "7일 연속"
        case .thirtyDayStreak: return "30일 연속"
        case .quizMaster: return "퀴즈 마스터"
        case .quizEnthusiast: return "퀴즈 매니아"
        }
    }

    var description: String {
        switch self {
        case .firstStep: return "첫 레슨을 완료했습니다"
        case .wordCollector50: return "단어 50개를 저장했습니다"
        case .wordCollector100: return "단어 100개를 저장했습니다"
        case .sevenDayStreak: return "7일 연속 학습했습니다"
        case .thirtyDayStreak: return "30일 연속 학습했습니다"
        case .quizMaster: return "퀴즈 정답률 90% 이상 (20회 이상)"
        case .quizEnthusiast: return "퀴즈 100회를 완료했습니다"
        }
    }

    var icon: String {
        switch self {
        case .firstStep: return "star.fill"
        case .wordCollector50: return "book.fill"
        case .wordCollector100: return "books.vertical.fill"
        case .sevenDayStreak: return "flame.fill"
        case .thirtyDayStreak: return "flame.circle.fill"
        case .quizMaster: return "crown.fill"
        case .quizEnthusiast: return "brain.head.profile.fill"
        }
    }
}

struct EarnedBadge: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID?
    let badgeType: String
    let earnedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case badgeType = "badge_type"
        case earnedAt = "earned_at"
    }
}
