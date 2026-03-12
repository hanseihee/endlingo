import SwiftUI

@Observable
@MainActor
final class LessonViewModel {
    var lesson: DailyLesson?
    var isLoading = false
    var errorMessage: String?

    func loadTodayLesson() async {
        guard let levelRaw = UserDefaults.standard.string(forKey: "selectedLevel"),
              let envRaw = UserDefaults.standard.string(forKey: "selectedEnvironment"),
              let level = EnglishLevel(rawValue: levelRaw),
              let environment = LearningEnvironment(rawValue: envRaw) else {
            errorMessage = "설정을 먼저 완료해주세요"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            lesson = try await LessonService.shared.fetchTodayLesson(
                level: level,
                environment: environment
            )
        } catch {
            errorMessage = "오늘의 레슨을 불러올 수 없습니다"
        }

        isLoading = false
    }
}
