import Foundation

final class LessonService {
    static let shared = LessonService()

    private let decoder = JSONDecoder()

    private var cache: [String: DailyLesson] = [:]
    private var cacheDate: String?

    private init() {}

    func fetchTodayLesson(level: EnglishLevel, environment: LearningEnvironment) async throws -> DailyLesson {
        try await fetchLesson(date: SupabaseConfig.todayDateString, level: level, environment: environment)
    }

    func fetchLesson(date: String, level: EnglishLevel, environment: LearningEnvironment) async throws -> DailyLesson {
        let cacheKey = "\(date)_\(level.rawValue)_\(environment.rawValue)"

        if let cached = cache[cacheKey] {
            return cached
        }

        let urlString = "\(SupabaseConfig.restBaseURL)/daily_lessons?select=*&date=eq.\(date)&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&limit=1"

        guard let url = URL(string: urlString) else { throw LessonError.notFound }

        var request = URLRequest(url: url)
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let lessons = try decoder.decode([DailyLesson].self, from: data)

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
