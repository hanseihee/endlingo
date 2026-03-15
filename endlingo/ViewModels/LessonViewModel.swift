import SwiftUI

@Observable
@MainActor
final class LessonViewModel {
    var lesson: DailyLesson?
    var isLoading = false
    var errorMessage: String?
    var selectedDate: Date = Date()

    private static let kstCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }()

    private static let kstFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f
    }()

    /// 오늘 포함 최근 11일 (왼쪽=과거, 오른쪽=오늘)
    var availableDates: [Date] {
        let today = Self.kstCalendar.startOfDay(for: Date())
        return (0...10).compactMap { Self.kstCalendar.date(byAdding: .day, value: -$0, to: today) }.reversed()
    }

    var isToday: Bool {
        Self.kstCalendar.isDateInToday(selectedDate)
    }

    func dateString(for date: Date) -> String {
        Self.kstFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "M/d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "E"
        return f
    }()

    func dayLabel(for date: Date) -> String {
        if Self.kstCalendar.isDateInToday(date) { return "오늘" }
        return Self.dayFormatter.string(from: date)
    }

    func weekdayLabel(for date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        Task { await loadLesson() }
    }

    func loadTodayLesson() async {
        selectedDate = Date()
        await loadLesson()
    }

    func loadLesson() async {
        guard let levelRaw = UserDefaults.standard.string(forKey: "selectedLevel"),
              let envRaw = UserDefaults.standard.string(forKey: "selectedEnvironment"),
              let level = EnglishLevel(rawValue: levelRaw),
              let environment = LearningEnvironment(rawValue: envRaw) else {
            errorMessage = "설정을 먼저 완료해주세요"
            return
        }

        isLoading = true
        errorMessage = nil

        let dateStr = dateString(for: selectedDate)

        do {
            lesson = try await LessonService.shared.fetchLesson(
                date: dateStr,
                level: level,
                environment: environment
            )
            AnalyticsService.logLessonView(level: levelRaw, environment: envRaw, date: dateStr)
        } catch {
            if isToday {
                errorMessage = "오늘의 레슨을 불러올 수 없습니다"
            } else {
                errorMessage = "해당 날짜의 레슨이 없습니다"
            }
        }

        isLoading = false
    }
}
