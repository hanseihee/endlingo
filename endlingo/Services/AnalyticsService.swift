import Foundation
import FirebaseAnalytics

/// Firebase Analytics 래퍼 - 앱 전체 이벤트 추적
enum AnalyticsService {

    // MARK: - 학습

    static func logLessonView(level: String, environment: String, date: String) {
        Analytics.logEvent("lesson_view", parameters: [
            "level": level,
            "environment": environment,
            "date": date,
        ])
    }

    // MARK: - 단어 / 문법

    static func logWordSave(word: String) {
        Analytics.logEvent("word_save", parameters: ["word": word])
    }

    static func logGrammarSave(pattern: String) {
        Analytics.logEvent("grammar_save", parameters: ["pattern": pattern])
    }

    // MARK: - 퀴즈

    static func logQuizStart(type: String, source: String) {
        Analytics.logEvent("quiz_start", parameters: ["quiz_type": type, "source": source])
    }

    static func logQuizComplete(type: String, correct: Int, total: Int, xp: Int) {
        Analytics.logEvent("quiz_complete", parameters: [
            "quiz_type": type,
            "correct": correct,
            "total": total,
            "accuracy": total > 0 ? correct * 100 / total : 0,
            "xp_earned": xp,
        ])
    }

    // MARK: - 따라 읽기

    static func logPronunciationPractice(score: Int) {
        Analytics.logEvent("pronunciation_practice", parameters: ["score": score])
    }

    // MARK: - 온보딩

    static func logOnboardingComplete(level: String, environment: String) {
        Analytics.logEvent("onboarding_complete", parameters: ["level": level, "environment": environment])
    }

    // MARK: - 화면 조회

    static func logScreen(_ name: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [AnalyticsParameterScreenName: name])
    }

    // MARK: - 사용자 속성

    static func setUserProperties(level: String?, environment: String?, streak: Int) {
        Analytics.setUserProperty(level, forName: "english_level")
        Analytics.setUserProperty(environment, forName: "learning_environment")
        Analytics.setUserProperty("\(streak)", forName: "current_streak")
    }
}
