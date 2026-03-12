import Foundation

enum BadgeCategory: String, CaseIterable {
    case learning = "학습"
    case vocabulary = "단어"
    case streak = "연속 학습"
    case quiz = "퀴즈"
    case level = "레벨"
}

enum BadgeType: String, Codable, CaseIterable, Identifiable {
    // 학습
    case firstStep = "first_step"
    case learning7 = "learning_7"
    case learning30 = "learning_30"
    case learning100 = "learning_100"
    case learning365 = "learning_365"

    // 단어
    case word10 = "word_10"
    case word50 = "word_50"
    case word100 = "word_100"
    case word300 = "word_300"
    case word500 = "word_500"
    case word1000 = "word_1000"

    // 연속 학습
    case streak3 = "streak_3"
    case streak7 = "streak_7"
    case streak14 = "streak_14"
    case streak30 = "streak_30"
    case streak60 = "streak_60"
    case streak100 = "streak_100"
    case streak365 = "streak_365"

    // 퀴즈
    case quizFirst = "quiz_first"
    case quiz10 = "quiz_10"
    case quiz50 = "quiz_50"
    case quiz100 = "quiz_100"
    case quiz500 = "quiz_500"
    case quizPerfect10 = "quiz_perfect_10"
    case quizAccuracy80 = "quiz_accuracy_80"
    case quizAccuracy90 = "quiz_accuracy_90"

    // 레벨
    case level5 = "level_5"
    case level10 = "level_10"
    case level20 = "level_20"
    case level50 = "level_50"

    var id: String { rawValue }

    var category: BadgeCategory {
        switch self {
        case .firstStep, .learning7, .learning30, .learning100, .learning365:
            return .learning
        case .word10, .word50, .word100, .word300, .word500, .word1000:
            return .vocabulary
        case .streak3, .streak7, .streak14, .streak30, .streak60, .streak100, .streak365:
            return .streak
        case .quizFirst, .quiz10, .quiz50, .quiz100, .quiz500, .quizPerfect10, .quizAccuracy80, .quizAccuracy90:
            return .quiz
        case .level5, .level10, .level20, .level50:
            return .level
        }
    }

    var title: String {
        switch self {
        // 학습
        case .firstStep: return "첫 걸음"
        case .learning7: return "일주일 학습"
        case .learning30: return "한 달 학습"
        case .learning100: return "100일 학습"
        case .learning365: return "1년 학습"
        // 단어
        case .word10: return "단어 입문"
        case .word50: return "단어 수집가"
        case .word100: return "단어 애호가"
        case .word300: return "단어 전문가"
        case .word500: return "단어 박사"
        case .word1000: return "단어 마스터"
        // 스트릭
        case .streak3: return "3일 연속"
        case .streak7: return "일주일 연속"
        case .streak14: return "2주 연속"
        case .streak30: return "한 달 연속"
        case .streak60: return "두 달 연속"
        case .streak100: return "100일 연속"
        case .streak365: return "1년 연속"
        // 퀴즈
        case .quizFirst: return "첫 퀴즈"
        case .quiz10: return "퀴즈 10회"
        case .quiz50: return "퀴즈 50회"
        case .quiz100: return "퀴즈 매니아"
        case .quiz500: return "퀴즈 중독"
        case .quizPerfect10: return "퍼펙트 게임"
        case .quizAccuracy80: return "우등생"
        case .quizAccuracy90: return "퀴즈 마스터"
        // 레벨
        case .level5: return "Lv.5 달성"
        case .level10: return "Lv.10 달성"
        case .level20: return "Lv.20 달성"
        case .level50: return "Lv.50 달성"
        }
    }

    var description: String {
        switch self {
        case .firstStep: return "첫 레슨을 완료했습니다"
        case .learning7: return "총 7일 학습했습니다"
        case .learning30: return "총 30일 학습했습니다"
        case .learning100: return "총 100일 학습했습니다"
        case .learning365: return "총 365일 학습했습니다"
        case .word10: return "단어 10개를 저장했습니다"
        case .word50: return "단어 50개를 저장했습니다"
        case .word100: return "단어 100개를 저장했습니다"
        case .word300: return "단어 300개를 저장했습니다"
        case .word500: return "단어 500개를 저장했습니다"
        case .word1000: return "단어 1,000개를 저장했습니다"
        case .streak3: return "3일 연속 학습했습니다"
        case .streak7: return "7일 연속 학습했습니다"
        case .streak14: return "14일 연속 학습했습니다"
        case .streak30: return "30일 연속 학습했습니다"
        case .streak60: return "60일 연속 학습했습니다"
        case .streak100: return "100일 연속 학습했습니다"
        case .streak365: return "365일 연속 학습했습니다"
        case .quizFirst: return "첫 퀴즈를 완료했습니다"
        case .quiz10: return "퀴즈 10회를 완료했습니다"
        case .quiz50: return "퀴즈 50회를 완료했습니다"
        case .quiz100: return "퀴즈 100회를 완료했습니다"
        case .quiz500: return "퀴즈 500회를 완료했습니다"
        case .quizPerfect10: return "퀴즈 10문제 연속 정답"
        case .quizAccuracy80: return "정답률 80% 이상 (50회 이상)"
        case .quizAccuracy90: return "정답률 90% 이상 (50회 이상)"
        case .level5: return "레벨 5에 도달했습니다"
        case .level10: return "레벨 10에 도달했습니다"
        case .level20: return "레벨 20에 도달했습니다"
        case .level50: return "레벨 50에 도달했습니다"
        }
    }

    var icon: String {
        switch self {
        case .firstStep: return "star.fill"
        case .learning7: return "calendar.badge.clock"
        case .learning30: return "calendar"
        case .learning100: return "calendar.badge.checkmark"
        case .learning365: return "calendar.circle.fill"
        case .word10: return "textformat.abc"
        case .word50: return "book.fill"
        case .word100: return "books.vertical.fill"
        case .word300: return "text.book.closed.fill"
        case .word500: return "graduationcap.fill"
        case .word1000: return "trophy.fill"
        case .streak3: return "flame"
        case .streak7: return "flame.fill"
        case .streak14: return "flame.circle"
        case .streak30: return "flame.circle.fill"
        case .streak60: return "bolt.fill"
        case .streak100: return "bolt.circle.fill"
        case .streak365: return "bolt.shield.fill"
        case .quizFirst: return "questionmark.circle.fill"
        case .quiz10: return "brain"
        case .quiz50: return "brain.fill"
        case .quiz100: return "brain.head.profile.fill"
        case .quiz500: return "sparkles"
        case .quizPerfect10: return "crown.fill"
        case .quizAccuracy80: return "medal.fill"
        case .quizAccuracy90: return "medal.star.fill"
        case .level5: return "arrow.up.circle"
        case .level10: return "arrow.up.circle.fill"
        case .level20: return "shield.fill"
        case .level50: return "shield.checkered"
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
