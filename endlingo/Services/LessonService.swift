import Foundation

@MainActor
final class LessonService {
    static let shared = LessonService()

    private var cache: [String: DailyLesson] = [:]
    private var cachedToday: String?
    private var cachedLanguage: String?

    private init() {}

    func fetchTodayLesson(level: EnglishLevel, environment: LearningEnvironment) async throws -> DailyLesson {
        try await fetchLesson(date: SupabaseConfig.todayDateString, level: level, environment: environment)
    }

    /// 현재 UI 로케일 기반 번역 언어 코드 (ko/ja/vi).
    /// 지원하지 않는 언어는 "ko"로 폴백.
    private var currentLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "ko"
        return ["ko", "ja", "vi"].contains(code) ? code : "ko"
    }

    /// 캐시 강제 초기화 (pull-to-refresh, 언어 변경 시)
    func clearCache() {
        cache.removeAll()
        cachedToday = nil
        cachedLanguage = nil
    }

    /// 문장 배열 퀴즈용: 여러 레슨에서 문장 풀을 가져옴.
    /// 번역이 아직 생성되지 않은 row 는 제외 — 빈 문자열 답안 표시 방지.
    func fetchSentencePool(level: EnglishLevel, environment: LearningEnvironment) async -> [Scenario] {
        let lang = currentLanguage
        let select = Self.lessonSelect(language: lang)
        let query = "\(select)&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&order=date.desc&limit=10"
        let rows: [DailyLessonRow] = await SupabaseAPI.fetch("daily_lessons_v2", query: query)
        return rows
            .filter { $0.hasAnyTranslation }
            .flatMap { $0.resolved().scenarios }
    }

    func fetchLesson(date: String, level: EnglishLevel, environment: LearningEnvironment) async throws -> DailyLesson {
        let today = SupabaseConfig.todayDateString
        let lang = currentLanguage

        // 날짜 또는 언어가 바뀌면 캐시 무효화
        if cachedToday != today || cachedLanguage != lang {
            cache.removeAll()
            cachedToday = today
            cachedLanguage = lang
        }

        let cacheKey = "\(date)_\(level.rawValue)_\(environment.rawValue)"

        if let cached = cache[cacheKey] {
            return cached
        }

        // v2 테이블 조회 — JSONB path select 로 현재 언어 + ko fallback 만 서버에서 추출.
        // translations 전체를 로드하는 대신 필요한 언어 객체만 내려와 bandwidth 절감.
        let select = Self.lessonSelect(language: lang)
        let query = "\(select)&date=eq.\(date)&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&limit=1"
        let rows: [DailyLessonRow] = await SupabaseAPI.fetch("daily_lessons_v2", query: query)

        guard let row = rows.first else {
            throw LessonError.notFound
        }

        // 번역이 아직 생성되지 않은 row (영어 cron 직후 ~5분 윈도우) 는 "준비 중" 으로 처리.
        // 그렇지 않으면 context/sentenceKo/grammar.explanation 이 빈 문자열로 렌더링됨.
        guard row.hasAnyTranslation else {
            throw LessonError.notFound
        }

        let lesson = row.resolved()
        cache[cacheKey] = lesson
        return lesson
    }

    /// PostgREST JSONB path select 로 현재 언어 + ko fallback 만 로드하는 select 절 생성.
    /// daily_lessons_v2 의 translations 가 4개 언어 (ko/ja/vi + 기타) 를 포함하므로,
    /// 필요한 언어 객체만 명시적으로 선택해 응답 크기 ~65% 절감.
    private static func lessonSelect(language: String) -> String {
        let base = "id,date,level,environment,theme_en,scenarios"
        if language == "ko" {
            return "select=\(base),translation:translations->ko"
        }
        return "select=\(base),translation:translations->\(language),fallback:translations->ko"
    }
}

enum LessonError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: return String(localized: "오늘의 레슨이 아직 준비되지 않았습니다")
        }
    }
}
