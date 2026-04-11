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

/// daily_lessons_v2 테이블 row. 영어 콘텐츠 + 현재 언어 번역.
///
/// 쿼리에서 PostgREST JSONB path select 로 필요한 언어만 서버에서 추출.
///   translation: 현재 UI 로케일 번역 (vi 사용자면 vi)
///   fallback:    ko 번역 (번역이 아직 생성되지 않은 경우 fallback)
/// 두 필드 모두 optional — 응답 크기 최소화를 위해 언어 객체만 내려옴.
struct DailyLessonRow: Codable, Identifiable {
    let id: UUID
    let date: String
    let level: String
    let environment: String
    let themeEn: String
    let scenarios: [EnglishScenarioRow]
    let translation: LessonTranslation?
    let fallback: LessonTranslation?

    enum CodingKeys: String, CodingKey {
        case id, date, level, environment, scenarios, translation, fallback
        case themeEn = "theme_en"
    }

    /// 번역이 하나라도 있는지 (서버 사이드 필터링용 가드).
    var hasAnyTranslation: Bool {
        translation != nil || fallback != nil
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
    /// DailyLessonRow 를 DailyLesson 으로 해석.
    /// 언어 선택은 이미 서버 쿼리(translation:translations->\(lang))에서 끝났고,
    /// 여기서는 translation → fallback(ko) → English-only 순으로 사용.
    func resolved() -> DailyLesson {
        let tr = translation ?? fallback
        let hasNative = translation != nil

        let resolvedThemeNative = tr?.theme ?? themeEn

        let resolvedScenarios = scenarios.map { eng -> Scenario in
            let scenarioTr = tr?.scenarios.first { $0.order == eng.order }

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
