import Foundation
import SwiftUI

@Observable
@MainActor
final class GamificationService {
    static let shared = GamificationService()

    private(set) var stats = UserStats()
    private(set) var learningRecords: [LearningRecord] = []
    private(set) var quizResults: [QuizResult] = []
    private(set) var earnedBadges: [EarnedBadge] = []
    private(set) var newBadge: BadgeType?

    // MARK: - XP Rewards

    enum XP {
        static let lessonView = 10
        static let wordSave = 5
        static let quizCorrect = 3
    }

    private var streakMultiplier: Int {
        stats.currentStreak >= 7 ? 2 : 1
    }

    // MARK: - Private

    private var auth: AuthService { AuthService.shared }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let recordsFileURL: URL
    private let quizFileURL: URL
    private let badgesFileURL: URL
    private let statsFileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordsFileURL = docs.appendingPathComponent("learning_records.json")
        quizFileURL = docs.appendingPathComponent("quiz_results.json")
        badgesFileURL = docs.appendingPathComponent("earned_badges.json")
        statsFileURL = docs.appendingPathComponent("user_stats.json")
        loadLocal()
        recalculateStats()
    }

    // MARK: - Public API

    /// 레슨 열람 시 호출 (하루 1회만 XP 지급)
    func recordLessonView(level: String, environment: String) {
        let today = SupabaseConfig.todayDateString
        guard !learningRecords.contains(where: { $0.date == today }) else { return }

        let xp = XP.lessonView * streakMultiplier
        let record = LearningRecord(
            id: UUID(), userId: auth.userId,
            date: today, level: level, environment: environment,
            xpEarned: xp, createdAt: Date()
        )

        learningRecords.append(record)

        if auth.isLoggedIn {
            Task { await remoteInsert(record, table: "learning_records") }
        } else {
            persistLocal(learningRecords, to: recordsFileURL)
        }

        stats.totalXP += xp
        recalculateStats()
        checkBadges()
    }

    /// 단어 저장 시 XP 지급
    func awardWordSaveXP() {
        let xp = XP.wordSave * streakMultiplier
        stats.totalXP += xp
        stats.recalculateLevel()
        persistStats()
        checkBadges()
    }

    /// 퀴즈 답변 기록
    func recordQuizAnswer(wordId: UUID, word: String, quizType: String, isCorrect: Bool) {
        let xp = isCorrect ? XP.quizCorrect * streakMultiplier : 0
        let result = QuizResult(
            id: UUID(), userId: auth.userId,
            date: SupabaseConfig.todayDateString, quizType: quizType,
            wordId: wordId, word: word,
            isCorrect: isCorrect, xpEarned: xp, createdAt: Date()
        )

        quizResults.append(result)

        if auth.isLoggedIn {
            Task { await remoteInsert(result, table: "quiz_results") }
        } else {
            persistLocal(quizResults, to: quizFileURL)
        }

        stats.totalXP += xp
        stats.totalQuizzes += 1
        if isCorrect { stats.correctQuizzes += 1 }
        stats.recalculateLevel()
        persistStats()
        checkBadges()
    }

    /// 캘린더용: 특정 달의 학습 날짜 → XP 맵
    func xpByDate(year: Int, month: Int) -> [String: Int] {
        let prefix = String(format: "%04d-%02d", year, month)
        var map: [String: Int] = [:]
        for record in learningRecords where record.date.hasPrefix(prefix) {
            map[record.date, default: 0] += record.xpEarned
        }
        // 퀴즈 XP도 합산
        for result in quizResults where result.date.hasPrefix(prefix) {
            map[result.date, default: 0] += result.xpEarned
        }
        return map
    }

    /// 배지 획득 알림 초기화
    func dismissNewBadge() {
        newBadge = nil
    }

    // MARK: - 주간 비교

    struct WeekStats {
        var learningDays: Int = 0
        var totalXP: Int = 0
        var quizCount: Int = 0
        var quizCorrect: Int = 0
        var wordsSaved: Int = 0

        var quizAccuracy: Double {
            quizCount > 0 ? Double(quizCorrect) / Double(quizCount) * 100 : 0
        }
    }

    func weekStats(for weekStart: Date) -> WeekStats {
        let cal = kstCalendar
        let dates = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let dateStrings = Set(dates.map { kstFormatter.string(from: $0) })

        var s = WeekStats()
        s.learningDays = Set(learningRecords.filter { dateStrings.contains($0.date) }.map(\.date)).count
        let weekRecordXP = learningRecords.filter { dateStrings.contains($0.date) }.reduce(0) { $0 + $1.xpEarned }
        let weekQuizXP = quizResults.filter { dateStrings.contains($0.date) }.reduce(0) { $0 + $1.xpEarned }
        s.totalXP = weekRecordXP + weekQuizXP
        let weekQuiz = quizResults.filter { dateStrings.contains($0.date) }
        s.quizCount = weekQuiz.count
        s.quizCorrect = weekQuiz.filter(\.isCorrect).count
        s.wordsSaved = VocabularyService.shared.words.filter { dateStrings.contains($0.lessonDate) }.count
        return s
    }

    /// 이번 주 월요일
    var thisWeekStart: Date {
        let cal = kstCalendar
        var c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        c.weekday = 2 // 월요일
        return cal.date(from: c) ?? Date()
    }

    /// 지난 주 월요일
    var lastWeekStart: Date {
        kstCalendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart
    }

    // MARK: - 활동 타임라인

    struct ActivityItem: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let text: String
        let xp: Int
        let date: Date
    }

    func recentActivities(days: Int = 7) -> [String: [ActivityItem]] {
        let cal = kstCalendar
        let cutoff = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date()))!

        var items: [ActivityItem] = []

        // 레슨
        for r in learningRecords where r.createdAt >= cutoff {
            items.append(ActivityItem(
                icon: "book.fill", color: .blue,
                text: "레슨 완료", xp: r.xpEarned, date: r.createdAt
            ))
        }

        // 퀴즈 (날짜별 묶기)
        let quizByDate = Dictionary(grouping: quizResults.filter { $0.createdAt >= cutoff }, by: \.date)
        for (_, results) in quizByDate {
            let correct = results.filter(\.isCorrect).count
            let total = results.count
            let xp = results.reduce(0) { $0 + $1.xpEarned }
            let date = results.first?.createdAt ?? Date()
            items.append(ActivityItem(
                icon: "brain.head.profile.fill", color: .purple,
                text: "퀴즈 \(correct)/\(total) 정답", xp: xp, date: date
            ))
        }

        // 단어 저장
        let savedByDate = Dictionary(grouping: VocabularyService.shared.words.filter { $0.savedAt >= cutoff }, by: \.lessonDate)
        for (_, words) in savedByDate {
            let xp = words.count * XP.wordSave
            let date = words.first?.savedAt ?? Date()
            items.append(ActivityItem(
                icon: "bookmark.fill", color: .green,
                text: "단어 \(words.count)개 저장", xp: xp, date: date
            ))
        }

        // 날짜별 그룹핑 (최신순)
        items.sort { $0.date > $1.date }
        var grouped: [String: [ActivityItem]] = [:]
        for item in items {
            let key = kstFormatter.string(from: item.date)
            grouped[key, default: []].append(item)
        }
        return grouped
    }

    // MARK: - Helpers

    private var kstCalendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        cal.firstWeekday = 2 // 월요일 시작
        return cal
    }

    private var kstFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f
    }

    // MARK: - Sync

    func syncAfterLogin() async {
        guard let userId = auth.userId else { return }

        // 로컬 데이터 업로드
        let localRecords = loadLocalArray(from: recordsFileURL, as: LearningRecord.self)
        for record in localRecords {
            let updated = LearningRecord(
                id: record.id, userId: userId,
                date: record.date, level: record.level,
                environment: record.environment,
                xpEarned: record.xpEarned, createdAt: record.createdAt
            )
            await remoteInsert(updated, table: "learning_records")
        }

        let localQuiz = loadLocalArray(from: quizFileURL, as: QuizResult.self)
        for result in localQuiz {
            let updated = QuizResult(
                id: result.id, userId: userId,
                date: result.date, quizType: result.quizType,
                wordId: result.wordId, word: result.word,
                isCorrect: result.isCorrect, xpEarned: result.xpEarned,
                createdAt: result.createdAt
            )
            await remoteInsert(updated, table: "quiz_results")
        }

        let localBadges = loadLocalArray(from: badgesFileURL, as: EarnedBadge.self)
        for badge in localBadges {
            let updated = EarnedBadge(
                id: badge.id, userId: userId,
                badgeType: badge.badgeType, earnedAt: badge.earnedAt
            )
            await remoteInsert(updated, table: "earned_badges")
        }

        // 로컬 파일 정리
        if !localRecords.isEmpty { try? FileManager.default.removeItem(at: recordsFileURL) }
        if !localQuiz.isEmpty { try? FileManager.default.removeItem(at: quizFileURL) }
        if !localBadges.isEmpty { try? FileManager.default.removeItem(at: badgesFileURL) }
        try? FileManager.default.removeItem(at: statsFileURL)

        // 서버에서 전체 로드
        await fetchRemote()
        recalculateStats()
    }

    func clearAfterLogout() {
        learningRecords = []
        quizResults = []
        earnedBadges = []
        stats = UserStats()
    }

    // MARK: - Streak Calculation

    private func recalculateStats() {
        // 스트릭 계산
        let dates = Set(learningRecords.map { $0.date }).sorted().reversed()
        var streak = 0
        let calendar = Calendar.current
        let kstTZ = TimeZone(identifier: "Asia/Seoul")!

        var checkDate = {
            var cal = Calendar.current
            cal.timeZone = kstTZ
            return cal.startOfDay(for: Date())
        }()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = kstTZ

        let todayStr = formatter.string(from: checkDate)

        // 오늘 학습 안 했으면 어제부터 체크
        if !dates.contains(todayStr) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        for _ in 0..<365 {
            let dateStr = formatter.string(from: checkDate)
            if dates.contains(dateStr) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        stats.currentStreak = streak
        stats.bestStreak = max(stats.bestStreak, streak)
        stats.totalLearningDays = Set(learningRecords.map { $0.date }).count

        // XP 재계산
        let recordXP = learningRecords.reduce(0) { $0 + $1.xpEarned }
        let quizXP = quizResults.reduce(0) { $0 + $1.xpEarned }
        let wordXP = VocabularyService.shared.words.count * XP.wordSave
        stats.totalXP = recordXP + quizXP + wordXP

        stats.totalQuizzes = quizResults.count
        stats.correctQuizzes = quizResults.filter { $0.isCorrect }.count
        stats.recalculateLevel()

        persistStats()
    }

    // MARK: - Badge Checking

    private func checkBadges() {
        let earned = Set(earnedBadges.map { $0.badgeType })
        let wordCount = VocabularyService.shared.words.count
        let days = stats.totalLearningDays
        let streak = stats.bestStreak
        let quizzes = stats.totalQuizzes
        let accuracy = stats.quizAccuracy
        let level = stats.userLevel

        let checks: [(BadgeType, Bool)] = [
            // 학습
            (.firstStep, !learningRecords.isEmpty),
            (.learning7, days >= 7),
            (.learning30, days >= 30),
            (.learning100, days >= 100),
            (.learning365, days >= 365),
            // 단어
            (.word10, wordCount >= 10),
            (.word50, wordCount >= 50),
            (.word100, wordCount >= 100),
            (.word300, wordCount >= 300),
            (.word500, wordCount >= 500),
            (.word1000, wordCount >= 1000),
            // 스트릭
            (.streak3, streak >= 3),
            (.streak7, streak >= 7),
            (.streak14, streak >= 14),
            (.streak30, streak >= 30),
            (.streak60, streak >= 60),
            (.streak100, streak >= 100),
            (.streak365, streak >= 365),
            // 퀴즈
            (.quizFirst, quizzes >= 1),
            (.quiz10, quizzes >= 10),
            (.quiz50, quizzes >= 50),
            (.quiz100, quizzes >= 100),
            (.quiz500, quizzes >= 500),
            (.quizPerfect10, hasConsecutiveCorrect(10)),
            (.quizAccuracy80, accuracy >= 80 && quizzes >= 50),
            (.quizAccuracy90, accuracy >= 90 && quizzes >= 50),
            // 레벨
            (.level5, level >= 5),
            (.level10, level >= 10),
            (.level20, level >= 20),
            (.level50, level >= 50),
        ]

        for (badge, unlocked) in checks {
            guard unlocked, !earned.contains(badge.rawValue) else { continue }

            let entry = EarnedBadge(
                id: UUID(), userId: auth.userId,
                badgeType: badge.rawValue, earnedAt: Date()
            )
            earnedBadges.append(entry)
            newBadge = badge

            if auth.isLoggedIn {
                Task { await remoteInsert(entry, table: "earned_badges") }
            } else {
                persistLocal(earnedBadges, to: badgesFileURL)
            }
        }
    }

    private func hasConsecutiveCorrect(_ count: Int) -> Bool {
        guard quizResults.count >= count else { return false }
        let sorted = quizResults.sorted { $0.createdAt < $1.createdAt }
        var consecutive = 0
        for result in sorted {
            consecutive = result.isCorrect ? consecutive + 1 : 0
            if consecutive >= count { return true }
        }
        return false
    }

    // MARK: - Remote (Supabase)

    private func remoteInsert<T: Encodable>(_ item: T, table: String) async {
        guard let token = await auth.accessToken,
              let url = URL(string: "\(SupabaseConfig.restBaseURL)/\(table)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal, resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? encoder.encode(item)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("Insert \(table) error: \(http.statusCode)")
            }
        } catch {
            print("Insert \(table) error: \(error)")
        }
    }

    private func fetchRemote() async {
        guard let token = await auth.accessToken else { return }

        async let records: [LearningRecord] = fetchTable("learning_records", token: token)
        async let quiz: [QuizResult] = fetchTable("quiz_results", token: token)
        async let badges: [EarnedBadge] = fetchTable("earned_badges", token: token)

        learningRecords = await records
        quizResults = await quiz
        earnedBadges = await badges
    }

    private func fetchTable<T: Decodable>(_ table: String, token: String) async -> [T] {
        guard let url = URL(string: "\(SupabaseConfig.restBaseURL)/\(table)?select=*&order=created_at.desc") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            // 비정상 응답 또는 빈 데이터
            guard let statusCode = http?.statusCode, statusCode == 200, !data.isEmpty else {
                return []
            }
            // 에러 응답(dictionary)인 경우 배열이 아님 → 건너뛰기
            if let first = data.first, first != UInt8(ascii: "[") {
                return []
            }
            return try decoder.decode([T].self, from: data)
        } catch {
            print("Fetch \(table) error: \(error)")
            return []
        }
    }

    // MARK: - Local Storage

    private func loadLocal() {
        learningRecords = loadLocalArray(from: recordsFileURL, as: LearningRecord.self)
        quizResults = loadLocalArray(from: quizFileURL, as: QuizResult.self)
        earnedBadges = loadLocalArray(from: badgesFileURL, as: EarnedBadge.self)

        if let data = try? Data(contentsOf: statsFileURL),
           let saved = try? decoder.decode(UserStats.self, from: data) {
            stats = saved
        }
    }

    private func loadLocalArray<T: Decodable>(from url: URL, as type: T.Type) -> [T] {
        guard let data = try? Data(contentsOf: url),
              let items = try? decoder.decode([T].self, from: data) else { return [] }
        return items
    }

    private func persistLocal<T: Encodable>(_ items: T, to url: URL) {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func persistStats() {
        persistLocal(stats, to: statsFileURL)
    }
}
