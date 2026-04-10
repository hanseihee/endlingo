import Foundation

// MARK: - View-facing types (뷰가 직접 사용)
// 뷰 수정을 최소화하기 위해 기존 프로퍼티 이름(themeKo, titleKo, sentenceKo)을 유지.
// 이제 "Ko" 접미사는 "현재 로케일의 네이티브 번역"을 뜻함 (ko/ja/zh 등).

struct DailyLesson: Identifiable {
    let id: UUID
    let date: String
    let level: String
    let environment: String
    let themeKo: String          // 현재 로케일 번역 (ko/ja/...)
    let themeEn: String
    let scenarios: [Scenario]
    /// 이 레슨의 네이티브 번역이 실제로 존재하는지 (false면 영어 fallback 상태)
    let hasNativeTranslation: Bool
}

struct Scenario: Identifiable {
    var id: Int { order }
    let order: Int
    let titleKo: String          // 현재 로케일 번역
    let titleEn: String
    let context: String          // 현재 로케일 번역
    let sentenceEn: String
    let sentenceKo: String       // 현재 로케일 번역
    let grammar: [GrammarPoint]
}

struct GrammarPoint: Identifiable {
    var id: String { pattern }
    let pattern: String
    let explanation: String
    let example: String?
}

// MARK: - DB-shape types (daily_lessons_v2 row decoder)

/// daily_lessons_v2 테이블 row. 영어 콘텐츠 + 다국어 번역 맵.
struct DailyLessonRow: Codable, Identifiable {
    let id: UUID
    let date: String
    let level: String
    let environment: String
    let themeEn: String
    let scenarios: [EnglishScenarioRow]
    let translations: [String: LessonTranslation]

    enum CodingKeys: String, CodingKey {
        case id, date, level, environment, scenarios, translations
        case themeEn = "theme_en"
    }
}

struct EnglishScenarioRow: Codable {
    let order: Int
    let titleEn: String
    let sentenceEn: String
    let grammar: [EnglishGrammarRow]

    enum CodingKeys: String, CodingKey {
        case order, grammar
        case titleEn = "title_en"
        case sentenceEn = "sentence_en"
    }
}

struct EnglishGrammarRow: Codable {
    let pattern: String
    let example: String?
}

struct LessonTranslation: Codable {
    let theme: String
    let scenarios: [ScenarioTranslation]
}

struct ScenarioTranslation: Codable {
    let order: Int
    let title: String
    let context: String
    let sentence: String
    let grammarExplanations: [String]

    enum CodingKeys: String, CodingKey {
        case order, title, context, sentence
        case grammarExplanations = "grammar_explanations"
    }
}

// MARK: - Resolver

extension DailyLessonRow {
    /// 현재 로케일에 맞춰 DailyLesson으로 해석.
    /// 우선순위: 요청 언어 → ko → ja → 영어 only fallback.
    func resolved(language: String) -> DailyLesson {
        let translation = translations[language]
            ?? translations["ko"]
            ?? translations["ja"]

        let hasNative = translations[language] != nil

        let resolvedThemeNative = translation?.theme ?? themeEn

        let resolvedScenarios = scenarios.map { eng -> Scenario in
            let scenarioTr = translation?.scenarios.first { $0.order == eng.order }

            let grammarPoints = eng.grammar.enumerated().map { idx, g -> GrammarPoint in
                let explanation = scenarioTr?.grammarExplanations.indices.contains(idx) == true
                    ? scenarioTr!.grammarExplanations[idx]
                    : ""
                return GrammarPoint(
                    pattern: g.pattern,
                    explanation: explanation,
                    example: g.example
                )
            }

            return Scenario(
                order: eng.order,
                titleKo: scenarioTr?.title ?? eng.titleEn,
                titleEn: eng.titleEn,
                context: scenarioTr?.context ?? "",
                sentenceEn: eng.sentenceEn,
                sentenceKo: scenarioTr?.sentence ?? "",
                grammar: grammarPoints
            )
        }

        return DailyLesson(
            id: id,
            date: date,
            level: level,
            environment: environment,
            themeKo: resolvedThemeNative,
            themeEn: themeEn,
            scenarios: resolvedScenarios,
            hasNativeTranslation: hasNative
        )
    }
}
