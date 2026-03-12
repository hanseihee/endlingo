import Foundation

final class LessonService {
    static let shared = LessonService()

    private let baseURL = "https://alvawqinuacabfnqduoy.supabase.co/rest/v1"
    private let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFsdmF3cWludWFjYWJmbnFkdW95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNjExNDgsImV4cCI6MjA4ODgzNzE0OH0.C-gnavFBHa-gIyvoGngaYfV6htDTiFyOmj5MemIlzhY"

    private let decoder = JSONDecoder()

    // 오늘 레슨 메모리 캐시
    private var cache: [String: DailyLesson] = [:]

    private init() {}

    func fetchTodayLesson(level: EnglishLevel, environment: LearningEnvironment) async throws -> DailyLesson {
        let today = Self.todayDateString()
        let cacheKey = "\(today)_\(level.rawValue)_\(environment.rawValue)"

        if let cached = cache[cacheKey] {
            return cached
        }

        let urlString = "\(baseURL)/daily_lessons?select=*&date=eq.\(today)&level=eq.\(level.rawValue)&environment=eq.\(environment.rawValue)&limit=1"

        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let lessons = try decoder.decode([DailyLesson].self, from: data)

        guard let lesson = lessons.first else {
            throw LessonError.notFound
        }

        cache[cacheKey] = lesson
        return lesson
    }

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return formatter.string(from: Date())
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
