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

    private var currentLanguage: String {
        Locale.current.language.languageCode?.identifier == "ja" ? "ja" : "ko"
    }

    /// 캐시 강제 초기화 (pull-to-refresh, 언어 변경 시)
    func clearCache() {
        cache.removeAll()
        cachedToday = nil
        cachedLanguage = nil
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

        // 해당 언어로 조회
        let query = "select=*&date=eq.\(date)&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&language=eq.\(lang)&limit=1"
        var lessons: [DailyLesson] = await SupabaseAPI.fetch("daily_lessons", query: query)

        // fallback: 해당 언어 없으면 한국어로
        if lessons.isEmpty && lang != "ko" {
            let fallbackQuery = "select=*&date=eq.\(date)&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&language=eq.ko&limit=1"
            lessons = await SupabaseAPI.fetch("daily_lessons", query: fallbackQuery)
        }

        guard let lesson = lessons.first else {
            throw LessonError.notFound
        }

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
