import Foundation

@MainActor
final class LessonService {
    static let shared = LessonService()

    private var cache: [String: DailyLesson] = [:]
    private var cachedToday: String?

    private init() {}

    func fetchTodayLesson(level: EnglishLevel, environment: LearningEnvironment) async throws -> DailyLesson {
        try await fetchLesson(date: SupabaseConfig.todayDateString, level: level, environment: environment)
    }

    func fetchLesson(date: String, level: EnglishLevel, environment: LearningEnvironment) async throws -> DailyLesson {
        // 날짜가 바뀌면 캐시 무효화
        let today = SupabaseConfig.todayDateString
        if cachedToday != today {
            cache.removeAll()
            cachedToday = today
        }

        let cacheKey = "\(date)_\(level.rawValue)_\(environment.rawValue)"

        if let cached = cache[cacheKey] {
            return cached
        }

        let query = "select=*&date=eq.\(date)&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&limit=1"
        let lessons: [DailyLesson] = await SupabaseAPI.fetch("daily_lessons", query: query)

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
        case .notFound: return "오늘의 레슨이 아직 준비되지 않았습니다"
        }
    }
}
