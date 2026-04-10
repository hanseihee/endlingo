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

    /// 현재 UI 로케일 기반 번역 언어 코드 (ko/ja/...).
    /// 지원하지 않는 언어는 "ko"로 폴백.
    private var currentLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "ko"
        return ["ko", "ja"].contains(code) ? code : "ko"
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
        let query = "select=*&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&order=date.desc&limit=10"
        let rows: [DailyLessonRow] = await SupabaseAPI.fetch("daily_lessons_v2", query: query)
        let lang = currentLanguage
        return rows
            .filter { !$0.translations.isEmpty }
            .flatMap { $0.resolved(language: lang).scenarios }
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

        // v2 테이블 조회 — 언어 필터 없음. 모든 번역이 한 row의 JSONB에 들어 있음.
        let query = "select=*&date=eq.\(date)&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&limit=1"
        let rows: [DailyLessonRow] = await SupabaseAPI.fetch("daily_lessons_v2", query: query)

        guard let row = rows.first else {
            throw LessonError.notFound
        }

        // 번역이 아직 생성되지 않은 row (영어 cron 직후 ~5분 윈도우) 는 "준비 중" 으로 처리.
        // 그렇지 않으면 context/sentenceKo/grammar.explanation 이 빈 문자열로 렌더링됨.
        guard !row.translations.isEmpty else {
            throw LessonError.notFound
        }

        let lesson = row.resolved(language: lang)
        cache[cacheKey] = lesson
        return lesson
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
