import Foundation

struct DailyLesson: Codable, Identifiable {
    let id: UUID
    let date: String
    let level: String
    let environment: String
    let language: String?
    let themeKo: String
    let themeEn: String
    let scenarios: [Scenario]

    enum CodingKeys: String, CodingKey {
        case id, date, level, environment, language, scenarios
        case themeKo = "theme_ko"
        case themeEn = "theme_en"
    }
}

struct Scenario: Codable, Identifiable {
    var id: Int { order }
    let order: Int
    let titleKo: String
    let titleEn: String
    let context: String
    let sentenceEn: String
    let sentenceKo: String
    let grammar: [GrammarPoint]

    enum CodingKeys: String, CodingKey {
        case order, context, grammar
        case titleKo = "title_ko"
        case titleEn = "title_en"
        case sentenceEn = "sentence_en"
        case sentenceKo = "sentence_ko"
    }
}

struct GrammarPoint: Codable, Identifiable {
    var id: String { pattern }
    let pattern: String
    let explanation: String
    let example: String?
}
